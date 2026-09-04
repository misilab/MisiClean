//
//  SelfUpdateManager.swift
//  MisiClean
//

import Foundation
import AppKit
import Combine

struct UpdateInfo {
    let version: String
    let downloadURL: URL
    let releaseNotes: String
    let publishedAt: Date?
}

enum InstallState: Equatable {
    case idle
    case downloading(progress: Double)
    case installing
    case done
    case failed(String)
    case cancelled
}

@MainActor
final class SelfUpdateManager: ObservableObject {
    static let shared = SelfUpdateManager()

    private static let feedURL = URL(string: "https://api.github.com/repos/misilab/MisiClean/releases/latest")!
    private static let lastCheckedKey = "fr.misilab.MisiClean.lastUpdateCheck"
    private static let cooldown: TimeInterval = 86_400

    @Published var availableUpdate: UpdateInfo? = nil
    @Published var isChecking = false
    @Published var lastChecked: Date? = nil
    @Published var checkError: String? = nil
    @Published var installState: InstallState = .idle

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var shouldAutoCheck: Bool {
        guard let last = lastChecked else { return true }
        return Date().timeIntervalSince(last) >= Self.cooldown
    }

    private init() {
        lastChecked = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date
    }

    // MARK: - Check

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        checkError = nil

        defer {
            isChecking = false
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Self.lastCheckedKey)
        }

        do {
            var request = URLRequest(url: Self.feedURL, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                checkError = "Serveur inaccessible"
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                availableUpdate = nil
                return
            }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard isNewerVersion(remoteVersion, than: currentVersion) else {
                availableUpdate = nil
                return
            }

            // Prefer .pkg, then .dmg, then html release page
            let downloadURL: URL
            if let assets = json["assets"] as? [[String: Any]] {
                let pkg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".pkg") == true })
                let dmg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true })
                let chosen = pkg ?? dmg
                if let asset = chosen,
                   let urlStr = asset["browser_download_url"] as? String,
                   let url = URL(string: urlStr) {
                    downloadURL = url
                } else if let htmlStr = json["html_url"] as? String, let url = URL(string: htmlStr) {
                    downloadURL = url
                } else { availableUpdate = nil; return }
            } else if let htmlStr = json["html_url"] as? String, let url = URL(string: htmlStr) {
                downloadURL = url
            } else { availableUpdate = nil; return }

            let body = (json["body"] as? String) ?? ""
            var publishedAt: Date? = nil
            if let pubStr = json["published_at"] as? String {
                publishedAt = ISO8601DateFormatter().date(from: pubStr)
            }

            availableUpdate = UpdateInfo(
                version: remoteVersion,
                downloadURL: downloadURL,
                releaseNotes: body,
                publishedAt: publishedAt
            )
        } catch {
            checkError = error.localizedDescription
        }
    }

    // MARK: - Auto-install

    func downloadAndInstall() async {
        guard let update = availableUpdate else { return }
        installState = .downloading(progress: 0)

        do {
            let isPkg = update.downloadURL.lastPathComponent.hasSuffix(".pkg")
            let tmpPath = "/tmp/MisiClean_update.\(isPkg ? "pkg" : "dmg")"

            // 1. Download with progress
            try await downloadFile(from: update.downloadURL, to: tmpPath)
            installState = .installing

            // 2. Install
            if isPkg {
                try await installPKG(at: tmpPath)
            } else {
                try await installDMG(at: tmpPath)
            }

            installState = .done
            try? await Task.sleep(nanoseconds: 600_000_000)

            // 3. Relaunch new version
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-n", Bundle.main.bundleURL.path]
            try? p.run()
            NSApplication.shared.terminate(nil)

        } catch {
            // Error -128 = user cancelled the auth dialog
            if (error as NSError).code == -128 {
                installState = .cancelled
            } else {
                installState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Private helpers

    // URLSessionDownloadTask + delegate — télécharge en arrière-plan, zéro overhead MainActor
    private func downloadFile(from url: URL, to path: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = DownloadProgressDelegate(
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.installState = .downloading(progress: progress)
                    }
                },
                onComplete: { tmpURL, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let tmpURL else {
                        continuation.resume(throwing: URLError(.unknown))
                        return
                    }
                    do {
                        let dest = URL(fileURLWithPath: path)
                        try? FileManager.default.removeItem(at: dest)
                        try FileManager.default.moveItem(at: tmpURL, to: dest)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            )
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session          // retain session until download ends
            session.downloadTask(with: url).resume()
        }
    }

    // Runs `installer -pkg ... -target /` via AppleScript (shows macOS auth dialog once)
    private func installPKG(at path: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let safe = path.replacingOccurrences(of: "'", with: "'\\''")
            let source = "do shell script \"installer -pkg '\(safe)' -target /\" with administrator privileges"
            var errDict: NSDictionary?
            let script = NSAppleScript(source: source)
            script?.executeAndReturnError(&errDict)
            if let err = errDict {
                let code = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
                if code == -128 {
                    // User cancelled auth
                    throw NSError(domain: "MisiClean.Updater", code: -128,
                                  userInfo: [NSLocalizedDescriptionKey: "Annulé par l'utilisateur"])
                }
                let msg = (err["NSAppleScriptErrorMessage"] as? String)
                       ?? (err["NSAppleScriptErrorBriefMessage"] as? String)
                       ?? "Erreur d'installation"
                throw NSError(domain: "MisiClean.Updater", code: code,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }.value
    }

    // Fallback for .dmg: mount, copy via shell script after quit
    private func installDMG(at path: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let mp = Process()
            mp.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            mp.arguments = ["attach", path, "-nobrowse"]
            let pipe = Pipe()
            mp.standardOutput = pipe
            try mp.run()
            mp.waitUntilExit()

            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard let mountPath = out.components(separatedBy: "\n").reversed()
                .compactMap({ line -> String? in
                    let cols = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
                    return cols.last.flatMap { $0.hasPrefix("/Volumes/") ? $0 : nil }
                }).first
            else {
                throw NSError(domain: "MisiClean.Updater", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Impossible de monter le DMG"])
            }

            let fm = FileManager.default
            guard let appName = (try? fm.contentsOfDirectory(atPath: mountPath))?.first(where: { $0.hasSuffix(".app") }) else {
                throw NSError(domain: "MisiClean.Updater", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Application introuvable"])
            }

            let src = mountPath + "/" + appName
            let dst = Bundle.main.bundleURL.deletingLastPathComponent().path + "/" + appName
            let script = """
            #!/bin/bash
            sleep 2
            rm -rf '\(dst)'
            cp -rf '\(src)' '\(dst)'
            /usr/bin/hdiutil detach '\(mountPath)' -quiet 2>/dev/null
            open '\(dst)'
            rm -f "$0"
            """
            let scriptPath = "/tmp/misclean_updater.sh"
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: scriptPath)
            let sp = Process()
            sp.executableURL = URL(fileURLWithPath: "/bin/bash")
            sp.arguments = [scriptPath]
            try sp.run()
        }.value
    }

    func openDownloadPage() {
        guard let url = availableUpdate?.downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    func dismissUpdate() {
        availableUpdate = nil
        installState = .idle
    }

    private func isNewerVersion(_ remote: String, than local: String) -> Bool {
        remote.compare(local, options: .numeric) == .orderedDescending
    }
}

// MARK: - URLSession download delegate (background, with progress)

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    let onComplete: (URL?, Error?) -> Void
    // Retain the session so it lives until the download ends
    var session: URLSession?
    private var didComplete = false

    init(onProgress: @escaping (Double) -> Void,
         onComplete: @escaping (URL?, Error?) -> Void) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        didComplete = true
        onComplete(location, nil)
        self.session = nil
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if !didComplete {
            onComplete(nil, error ?? URLError(.unknown))
            self.session = nil
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
