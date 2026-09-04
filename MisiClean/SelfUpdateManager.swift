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

@MainActor
final class SelfUpdateManager: ObservableObject {
    static let shared = SelfUpdateManager()

    // Point this to your GitHub repo releases API
    private static let feedURL = URL(string: "https://api.github.com/repos/misilab/MisiClean/releases/latest")!
    private static let lastCheckedKey = "fr.misilab.MisiClean.lastUpdateCheck"
    private static let cooldown: TimeInterval = 86_400  // 24 h

    @Published var availableUpdate: UpdateInfo? = nil
    @Published var isChecking = false
    @Published var lastChecked: Date? = nil
    @Published var checkError: String? = nil

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

            // Prefer a .dmg asset; fall back to the HTML release page
            let downloadURL: URL
            if let assets = json["assets"] as? [[String: Any]],
               let dmg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
               let urlStr = dmg["browser_download_url"] as? String,
               let url = URL(string: urlStr) {
                downloadURL = url
            } else if let htmlStr = json["html_url"] as? String,
                      let url = URL(string: htmlStr) {
                downloadURL = url
            } else {
                availableUpdate = nil
                return
            }

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

    func openDownloadPage() {
        guard let url = availableUpdate?.downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    func dismissUpdate() {
        availableUpdate = nil
    }

    private func isNewerVersion(_ remote: String, than local: String) -> Bool {
        remote.compare(local, options: .numeric) == .orderedDescending
    }
}
