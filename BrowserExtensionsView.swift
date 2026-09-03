//
//  BrowserExtensionsView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct BrowserExtension: Identifiable {
    enum Browser: String, CaseIterable, Identifiable {
        case safari  = "Safari"
        case chrome  = "Chrome"
        case firefox = "Firefox"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .safari:  return "safari.fill"
            case .chrome:  return "globe"
            case .firefox: return "flame.fill"
            }
        }
        var accent: Color {
            switch self {
            case .safari:  return .teal
            case .chrome:  return Color(red: 0.26, green: 0.52, blue: 0.96)
            case .firefox: return .orange
            }
        }
    }

    let id = UUID()
    let name: String
    let version: String
    let browser: Browser
    let extensionID: String
    let sizeBytes: Int64
    let isEnabled: Bool
}

// MARK: - ViewModel

@MainActor
class BrowserExtensionsViewModel: ObservableObject {
    @Published var extensions: [BrowserExtension] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var browserFilter: BrowserExtension.Browser? = nil

    var filtered: [BrowserExtension] {
        guard let f = browserFilter else { return extensions }
        return extensions.filter { $0.browser == f }
    }

    var availableBrowsers: [BrowserExtension.Browser] {
        let seen = Set(extensions.map(\.browser.rawValue))
        return BrowserExtension.Browser.allCases.filter { seen.contains($0.rawValue) }
    }

    func load() async {
        isLoading = true; hasLoaded = true
        defer { isLoading = false }
        let result = await Task.detached(priority: .userInitiated) {
            BrowserExtensionsViewModel.loadAll()
        }.value
        withAnimation { extensions = result }
    }

    func openManager(for browser: BrowserExtension.Browser) {
        switch browser {
        case .safari:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.extensions?Safari")
                                    ?? URL(fileURLWithPath: "/Applications/Safari.app"))
        case .chrome:
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Google Chrome", "--args", "--new-window",
                              "--url", "chrome://extensions"]
            try? proc.run()
        case .firefox:
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Firefox", "--args", "-url", "about:addons"]
            try? proc.run()
        }
    }

    nonisolated static func loadAll() -> [BrowserExtension] {
        var result: [BrowserExtension] = []
        result += loadChrome()
        result += loadFirefox()
        result += loadSafari()
        return result.sorted { $0.browser.rawValue < $1.browser.rawValue || ($0.browser == $1.browser && $0.name < $1.name) }
    }

    // MARK: Chrome

    nonisolated private static func loadChrome() -> [BrowserExtension] {
        let fm = FileManager.default
        let base = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")
        guard fm.fileExists(atPath: base.path) else { return [] }

        var profileDirs: [URL] = []
        if let contents = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
            profileDirs = contents.filter { url in
                let name = url.lastPathComponent
                return name == "Default" || name.hasPrefix("Profile ")
            }
        }
        if profileDirs.isEmpty {
            profileDirs = [base.appendingPathComponent("Default")]
        }

        var extensions: [BrowserExtension] = []
        var seen = Set<String>()
        for profileDir in profileDirs {
            let extDir = profileDir.appendingPathComponent("Extensions")
            guard let extIDs = try? fm.contentsOfDirectory(at: extDir, includingPropertiesForKeys: nil) else { continue }
            for extID in extIDs {
                guard !seen.contains(extID.lastPathComponent) else { continue }
                // Find version directory (latest)
                guard let versions = try? fm.contentsOfDirectory(at: extID, includingPropertiesForKeys: nil)
                    .sorted(by: { $0.lastPathComponent > $1.lastPathComponent }),
                      let versionDir = versions.first else { continue }
                let manifestURL = versionDir.appendingPathComponent("manifest.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                var name = json["name"] as? String ?? extID.lastPathComponent
                let version = json["version"] as? String ?? ""
                let defaultLocale = json["default_locale"] as? String

                // Resolve localized name (__MSG_key__ pattern)
                if name.hasPrefix("__MSG_") {
                    let msgKey = name
                        .replacingOccurrences(of: "__MSG_", with: "")
                        .replacingOccurrences(of: "__", with: "")
                    name = resolveMsg(msgKey: msgKey, in: versionDir, locale: defaultLocale ?? "en")
                        ?? extID.lastPathComponent   // fallback to extension ID, not the raw __MSG__ string
                }
                let size = dirSize(at: versionDir)
                seen.insert(extID.lastPathComponent)
                extensions.append(BrowserExtension(
                    name: name, version: version, browser: .chrome,
                    extensionID: extID.lastPathComponent, sizeBytes: size, isEnabled: true))
            }
        }
        return extensions
    }

    nonisolated private static func resolveMsg(msgKey: String, in dir: URL, locale: String) -> String? {
        for loc in [locale, "en", "en_US"] {
            let msgFile = dir.appendingPathComponent("_locales/\(loc)/messages.json")
            guard let data = try? Data(contentsOf: msgFile),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entry = json[msgKey] as? [String: Any],
                  let msg = entry["message"] as? String else { continue }
            return msg
        }
        return nil
    }

    // MARK: Firefox

    nonisolated private static func loadFirefox() -> [BrowserExtension] {
        let fm = FileManager.default
        let profilesDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")
        guard let profiles = try? fm.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil) else { return [] }

        var extensions: [BrowserExtension] = []
        var seen = Set<String>()
        for profile in profiles {
            let extJSON = profile.appendingPathComponent("extensions.json")
            guard let data = try? Data(contentsOf: extJSON),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let addons = root["addons"] as? [[String: Any]] else { continue }
            for addon in addons {
                guard addon["type"] as? String == "extension" else { continue }
                let extID = addon["id"] as? String ?? ""
                guard !seen.contains(extID) else { continue }
                let locale = addon["defaultLocale"] as? [String: Any]
                let name = locale?["name"] as? String ?? extID
                let version = addon["version"] as? String ?? ""
                let active = addon["active"] as? Bool ?? true
                let size = (addon["size"] as? Int64) ?? 0
                guard !name.isEmpty, !extID.isEmpty else { continue }
                seen.insert(extID)
                extensions.append(BrowserExtension(
                    name: name, version: version, browser: .firefox,
                    extensionID: extID, sizeBytes: size, isEnabled: active))
            }
        }
        return extensions
    }

    // MARK: Safari

    nonisolated private static func loadSafari() -> [BrowserExtension] {
        let fm = FileManager.default
        // Try modern Safari extension plist
        let plistPath = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Safari/Extensions/Extensions.plist")
        guard let data = fm.contents(atPath: plistPath.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let installed = plist["Installed Extensions"] as? [[String: Any]] else { return [] }
        return installed.compactMap { ext in
            guard let name = ext["Archive File Name"] as? String ?? ext["Bundle Identifier"] as? String else { return nil }
            let displayName = (ext["Bundle Display Name"] as? String) ?? name
            let version = ext["CFBundleVersion"] as? String ?? ""
            let enabled = ext["Enabled"] as? Bool ?? true
            return BrowserExtension(
                name: displayName, version: version, browser: .safari,
                extensionID: name, sizeBytes: 0, isEnabled: enabled)
        }
    }

    nonisolated private static func dirSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var size: Int64 = 0
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true {
                size += Int64(v.fileSize ?? 0)
            }
        }
        return size
    }
}

// MARK: - Section View

struct BrowserExtensionsSection: View {
    @ObservedObject var vm: BrowserExtensionsViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isLoading || !vm.hasLoaded { loadingState }
            else if vm.extensions.isEmpty { emptyState }
            else { extList }
        }
        .onAppear { Task { await vm.load() } }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Extensions navigateur").font(.callout.weight(.semibold))
                Text("Safari, Chrome et Firefox — \(vm.extensions.count) extension\(vm.extensions.count != 1 ? "s" : "") détectée\(vm.extensions.count != 1 ? "s" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !vm.availableBrowsers.isEmpty {
                Picker("", selection: $vm.browserFilter) {
                    Text("Tous").tag(BrowserExtension.Browser?.none)
                    ForEach(vm.availableBrowsers) { b in Text(b.rawValue).tag(Optional(b)) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 220)
            }
            if vm.isLoading { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.load() } } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(vm.isLoading)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var loadingState: some View {
        VStack(spacing: 14) { Spacer(); ProgressView().scaleEffect(1.3)
            Text("Lecture des extensions…").foregroundStyle(.secondary); Spacer() }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "puzzlepiece.fill")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(Color.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text("Aucune extension trouvée").font(.title3.bold())
                Text("Aucune extension Safari, Chrome ou Firefox n'a été détectée sur ce Mac.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(32)
    }

    private var extList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(vm.filtered) { ext in
                        BrowserExtRow(ext: ext)
                    }
                }
                .padding(12)
            }
            Divider()
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(vm.filtered.count) extension\(vm.filtered.count != 1 ? "s" : "")")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            ForEach(vm.availableBrowsers) { browser in
                Button {
                    vm.openManager(for: browser)
                } label: {
                    Label("Gérer \(browser.rawValue)", systemImage: browser.icon)
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .tint(browser.accent)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Extension Row

struct BrowserExtRow: View {
    let ext: BrowserExtension

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ext.browser.accent.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: ext.browser.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(ext.browser.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ext.name).font(.body.weight(.medium)).lineLimit(1)
                    if !ext.isEnabled {
                        Text("Désactivée")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                HStack(spacing: 6) {
                    Text(ext.browser.rawValue).font(.caption).foregroundStyle(ext.browser.accent)
                    if !ext.version.isEmpty {
                        Text("v\(ext.version)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if ext.sizeBytes > 0 {
                Text(ext.sizeBytes.formattedSize)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .opacity(ext.isEnabled ? 1.0 : 0.55)
    }
}
