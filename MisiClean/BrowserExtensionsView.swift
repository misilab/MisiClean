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
            case .chrome:  return "circle.hexagongrid.fill"
            case .firefox: return "flame.fill"
            }
        }
        var accent: Color {
            switch self {
            case .safari:  return .blue
            case .chrome:  return .orange
            case .firefox: return Color(red: 0.9, green: 0.35, blue: 0.1)
            }
        }
    }

    let id = UUID()
    let browser: Browser
    let name: String
    let version: String
    let sizeBytes: Int64
    let isDisabled: Bool
    let dirURL: URL?
}

// MARK: - ViewModel

@MainActor
class BrowserExtensionsViewModel: ObservableObject {
    @Published var extensions: [BrowserExtension] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var filter: BrowserExtension.Browser? = nil

    var filtered: [BrowserExtension] {
        guard let f = filter else { return extensions }
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
            BrowserExtensionsViewModel.scanAll()
        }.value
        withAnimation { extensions = result }
    }

    nonisolated static func scanAll() -> [BrowserExtension] {
        var results: [BrowserExtension] = []
        results += scanSafari()
        results += scanChrome()
        results += scanFirefox()
        return results.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func scanSafari() -> [BrowserExtension] {
        let fm = FileManager.default
        let plistPath = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Safari/Extensions/Extensions.plist")

        guard let data = try? Data(contentsOf: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let installed = plist["Installed Extensions"] as? [[String: Any]] else { return [] }

        return installed.compactMap { ext -> BrowserExtension? in
            guard let name = ext["Archive File Name"] as? String ?? ext["Bundle Identifier"] as? String else { return nil }
            let isEnabled = ext["Enabled"] as? Bool ?? true
            let displayName = (name as NSString).deletingPathExtension
                .replacingOccurrences(of: "-", with: " ")
            return BrowserExtension(
                browser: .safari, name: displayName, version: "",
                sizeBytes: 0, isDisabled: !isEnabled, dirURL: nil)
        }
    }

    nonisolated private static func scanChrome() -> [BrowserExtension] {
        let fm = FileManager.default
        let chromeBase = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")
        guard fm.fileExists(atPath: chromeBase.path) else { return [] }

        var profiles: [URL] = []
        if let entries = try? fm.contentsOfDirectory(at: chromeBase, includingPropertiesForKeys: nil) {
            for e in entries {
                let name = e.lastPathComponent
                if name == "Default" || name.hasPrefix("Profile") { profiles.append(e) }
            }
        }

        var results: [BrowserExtension] = []
        for profile in profiles {
            let extDir = profile.appendingPathComponent("Extensions")
            guard let exts = try? fm.contentsOfDirectory(at: extDir, includingPropertiesForKeys: nil) else { continue }
            for extID in exts {
                guard let versions = try? fm.contentsOfDirectory(at: extID, includingPropertiesForKeys: nil),
                      let latest = versions.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last
                else { continue }
                let manifest = latest.appendingPathComponent("manifest.json")
                guard let data = try? Data(contentsOf: manifest),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                var name = json["name"] as? String ?? extID.lastPathComponent
                if name.hasPrefix("__MSG_") {
                    let msgKey = name.replacingOccurrences(of: "__MSG_", with: "").replacingOccurrences(of: "__", with: "")
                    let localeFile = latest.appendingPathComponent("_locales/en/messages.json")
                    if let locData = try? Data(contentsOf: localeFile),
                       let locJson = try? JSONSerialization.jsonObject(with: locData) as? [String: Any],
                       let msgObj = locJson[msgKey] as? [String: Any],
                       let msg = msgObj["message"] as? String {
                        name = msg
                    }
                }

                let version = json["version"] as? String ?? ""
                let size = dirSize(at: latest)
                results.append(BrowserExtension(
                    browser: .chrome, name: name, version: version,
                    sizeBytes: size, isDisabled: false, dirURL: latest))
            }
        }
        return results
    }

    nonisolated private static func scanFirefox() -> [BrowserExtension] {
        let fm = FileManager.default
        let ffBase = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")
        guard let profiles = try? fm.contentsOfDirectory(at: ffBase, includingPropertiesForKeys: nil) else { return [] }

        var results: [BrowserExtension] = []
        for profile in profiles {
            let extsFile = profile.appendingPathComponent("extensions.json")
            guard let data = try? Data(contentsOf: extsFile),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let addons = json["addons"] as? [[String: Any]] else { continue }

            for addon in addons {
                guard (addon["type"] as? String) == "extension" else { continue }
                let name = addon["defaultLocale"] as? [String: Any]
                let displayName = name?["name"] as? String ?? addon["id"] as? String ?? "Extension"
                let version = addon["version"] as? String ?? ""
                results.append(BrowserExtension(
                    browser: .firefox, name: displayName, version: version,
                    sizeBytes: 0, isDisabled: false, dirURL: nil))
            }
        }
        return results
    }

    nonisolated private static func dirSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var size: Int64 = 0
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
            else { extList; Divider(); footer }
        }
        .onAppear { Task { await vm.load() } }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Extensions navigateurs").font(.callout.weight(.semibold))
                Text("\(vm.extensions.count) extension\(vm.extensions.count != 1 ? "s" : "") détectée\(vm.extensions.count != 1 ? "s" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !vm.availableBrowsers.isEmpty {
                Picker("", selection: $vm.filter) {
                    Text("Tous").tag(BrowserExtension.Browser?.none)
                    ForEach(vm.availableBrowsers) { b in
                        Text(b.rawValue).tag(Optional(b))
                    }
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
            Text("Recherche des extensions…").foregroundStyle(.secondary); Spacer() }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(Color.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text("Aucune extension trouvée").font(.title3.bold())
                Text("Safari, Chrome et Firefox ont été inspectés. Aucune extension installée.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(32)
    }

    private var extList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(vm.filtered) { ext in
                    BrowserExtRow(ext: ext)
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(vm.filtered.count) extension\(vm.filtered.count != 1 ? "s" : "")")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            ForEach(BrowserExtension.Browser.allCases) { browser in
                if vm.availableBrowsers.contains(where: { $0 == browser }) {
                    Button("Gérer \(browser.rawValue)") { openExtensionManager(browser) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func openExtensionManager(_ browser: BrowserExtension.Browser) {
        switch browser {
        case .safari:
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.extensions")!)
        case .chrome:
            if let url = URL(string: "google-chrome://extensions") {
                NSWorkspace.shared.open(url)
            }
        case .firefox:
            if let url = URL(string: "about:addons") {
                NSWorkspace.shared.open(url)
            }
        }
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
                    .font(.system(size: 15))
                    .foregroundStyle(ext.browser.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ext.name).font(.body.weight(.medium)).lineLimit(1)
                    if ext.isDisabled {
                        Text("Désactivée")
                            .font(.caption2).foregroundStyle(.orange)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                HStack(spacing: 6) {
                    Text(ext.browser.rawValue)
                        .font(.caption).foregroundStyle(ext.browser.accent)
                    if !ext.version.isEmpty {
                        Text("v\(ext.version)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if ext.sizeBytes > 0 {
                Text(ext.sizeBytes.formattedSize)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(ext.isDisabled ? 0.015 : 0.03), in: RoundedRectangle(cornerRadius: 8))
        .opacity(ext.isDisabled ? 0.65 : 1.0)
    }
}
