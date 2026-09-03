//
//  PrivacyView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - ViewModel

@MainActor
class PrivacyViewModel: ObservableObject {
    @Published var items: [PrivacyItem] = PrivacyViewModel.defaultItems()
    @Published var isCleaning = false
    @Published var isScanning = false
    @Published var showResult = false
    @Published var clearedCount = 0
    @Published var browserAlert: String? = nil

    var selectedItems: [PrivacyItem] { items.filter(\.isSelected) }

    func measureSizes() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        for i in items.indices {
            let action = items[i].action
            let size = await Task.detached(priority: .userInitiated) {
                PrivacyViewModel.measure(action: action)
            }.value
            items[i].sizeBytes = size
        }
    }

    nonisolated static func measure(action: PrivacyAction) -> Int64 {
        guard case .deletePaths(let paths) = action else { return 0 }
        return paths.reduce(0) { total, url in
            let fm = FileManager.default
            guard fm.fileExists(atPath: url.path) else { return total }
            if let v = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               v.isRegularFile == true { return total + Int64(v.fileSize ?? 0) }
            var size: Int64 = 0
            let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
            guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return total }
            for case let f as URL in e {
                guard let rv = try? f.resourceValues(forKeys: keys), rv.isRegularFile == true else { continue }
                size += Int64(rv.fileSize ?? 0)
            }
            return total + size
        }
    }

    func clean(skipBrowserCheck: Bool = false) async {
        if !skipBrowserCheck, let warning = browserOpenWarning() {
            browserAlert = warning
            return
        }
        guard !isCleaning else { return }
        isCleaning = true
        defer { isCleaning = false }

        var count = 0
        for item in selectedItems {
            switch item.action {
            case .clearClipboard:
                NSPasteboard.general.clearContents()
                count += 1
            case .clearRecentItems:
                clearRecentItems()
                count += 1
            case .deletePaths(let paths):
                for path in paths where FileManager.default.fileExists(atPath: path.path) {
                    try? FileManager.default.trashItem(at: path, resultingItemURL: nil)
                }
                count += 1
            }
        }
        clearedCount = count
        for i in items.indices { items[i].sizeBytes = 0 }
        showResult = true
    }

    // Retourne un message d'avertissement si un navigateur ciblé est ouvert
    private func browserOpenWarning() -> String? {
        var open: [String] = []
        let safariItems = selectedItems.filter { item in
            if case .deletePaths(let paths) = item.action {
                return paths.contains { $0.path.contains("/Safari/") || $0.path.contains("com.apple.Safari") }
            }
            return false
        }
        let chromeItems = selectedItems.filter { item in
            if case .deletePaths(let paths) = item.action {
                return paths.contains { $0.path.contains("Chrome") }
            }
            return false
        }
        let ffItems = selectedItems.filter { item in
            if case .deletePaths(let paths) = item.action {
                return paths.contains { $0.path.contains("Firefox") }
            }
            return false
        }

        if !safariItems.isEmpty,
           !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty {
            open.append("Safari")
        }
        if !chromeItems.isEmpty,
           !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty {
            open.append("Google Chrome")
        }
        if !ffItems.isEmpty,
           !NSRunningApplication.runningApplications(withBundleIdentifier: "org.mozilla.firefox").isEmpty {
            open.append("Firefox")
        }

        guard !open.isEmpty else { return nil }
        let names = open.joined(separator: ", ")
        return "\(names) \(open.count > 1 ? "sont" : "est") en cours d'exécution.\n\nFermez \(open.count > 1 ? "ces navigateurs" : "ce navigateur") avant de nettoyer leur historique pour éviter une corruption des bases de données."
    }

    private func clearRecentItems() {
        let fm = FileManager.default
        let sharedList = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
        guard let files = try? fm.contentsOfDirectory(at: sharedList, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "sfl3" || $0.pathExtension == "sfl2" }) else { return }
        for file in files { try? fm.trashItem(at: file, resultingItemURL: nil) }
    }

    func setSelectAll(_ value: Bool) {
        withAnimation { for i in items.indices { items[i].isSelected = value } }
    }

    static func defaultItems() -> [PrivacyItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let lib  = home.appendingPathComponent("Library")

        func firefoxHistory() -> [URL] {
            let profilesDir = lib.appendingPathComponent("Application Support/Firefox/Profiles")
            guard let profiles = try? FileManager.default.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil) else { return [] }
            return profiles.flatMap { p in
                ["places.sqlite", "places.sqlite-wal", "places.sqlite-shm", "formhistory.sqlite"]
                    .map { p.appendingPathComponent($0) }
            }
        }

        return [
            PrivacyItem(name: "Presse-papiers",
                        description: "Efface le contenu actuel du presse-papiers",
                        icon: "doc.on.clipboard.fill", accent: .blue,
                        action: .clearClipboard),
            PrivacyItem(name: "Historique Safari",
                        description: "Navigation, formulaires et recherches récentes",
                        icon: "safari.fill", accent: .teal,
                        action: .deletePaths([
                            lib.appendingPathComponent("Safari/History.db"),
                            lib.appendingPathComponent("Safari/History.db-shm"),
                            lib.appendingPathComponent("Safari/History.db-wal"),
                            lib.appendingPathComponent("Safari/HistoryIndex.sk"),
                            lib.appendingPathComponent("Caches/com.apple.Safari"),
                        ])),
            PrivacyItem(name: "Historique Chrome",
                        description: "Navigation et recherches Google Chrome",
                        icon: "globe", accent: Color(red: 0.26, green: 0.52, blue: 0.96),
                        action: .deletePaths([
                            lib.appendingPathComponent("Application Support/Google/Chrome/Default/History"),
                            lib.appendingPathComponent("Application Support/Google/Chrome/Default/History-journal"),
                            lib.appendingPathComponent("Application Support/Google/Chrome/Default/Visited Links"),
                        ])),
            PrivacyItem(name: "Historique Firefox",
                        description: "Navigation et formulaires Firefox",
                        icon: "flame.fill", accent: .orange,
                        action: .deletePaths(firefoxHistory())),
            PrivacyItem(name: "Fichiers récents",
                        description: "Liste des documents et apps récemment ouverts",
                        icon: "clock.fill", accent: .yellow,
                        action: .clearRecentItems),
            PrivacyItem(name: "Cache QuickLook",
                        description: "Miniatures de prévisualisation des fichiers",
                        icon: "eye.fill", accent: .purple,
                        action: .deletePaths([
                            lib.appendingPathComponent("Application Support/Quick Look"),
                        ])),
            PrivacyItem(name: "Données iOS sur Mac",
                        description: "Photos, contacts et données synchronisées",
                        icon: "iphone.badge.play", accent: .pink,
                        action: .deletePaths([
                            lib.appendingPathComponent("Application Support/MobileSync/Devices"),
                        ])),
        ]
    }
}

// MARK: - Section

struct PrivacySection: View {
    @ObservedObject var vm: PrivacyViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    ForEach($vm.items) { $item in PrivacyItemRow(item: $item) }
                }
                .padding(12)
            }
            Divider()
            footer
        }
        .onAppear { Task { await vm.measureSizes() } }
        .alert("Confidentialité nettoyée", isPresented: $vm.showResult) {
            Button("OK") { }
        } message: {
            Text("\(vm.clearedCount) élément\(vm.clearedCount > 1 ? "s" : "") nettoyé\(vm.clearedCount > 1 ? "s" : "").")
        }
        .alert("Navigateur ouvert", isPresented: .init(
            get: { vm.browserAlert != nil },
            set: { if !$0 { vm.browserAlert = nil } }
        )) {
            Button("Annuler", role: .cancel) { vm.browserAlert = nil }
            Button("Nettoyer quand même", role: .destructive) {
                vm.browserAlert = nil
                Task { await vm.clean(skipBrowserCheck: true) }
            }
        } message: {
            Text(vm.browserAlert ?? "")
        }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nettoyage confidentialité").font(.callout.weight(.semibold))
                Text("Effacez vos traces de navigation et données personnelles")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isScanning {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Mesure…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Menu {
                Button("Tout sélectionner") { vm.setSelectAll(true) }
                Button("Tout désélectionner") { vm.setSelectAll(false) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(vm.selectedItems.count) élément\(vm.selectedItems.count != 1 ? "s" : "") sélectionné\(vm.selectedItems.count != 1 ? "s" : "")")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button { Task { await vm.clean() } } label: {
                Label(vm.isCleaning ? "Nettoyage…" : "Nettoyer", systemImage: "shield.fill")
            }
            .buttonStyle(.borderedProminent).tint(.indigo).controlSize(.large)
            .disabled(vm.selectedItems.isEmpty || vm.isCleaning)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Privacy Item Row

struct PrivacyItemRow: View {
    @Binding var item: PrivacyItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(item.accent.opacity(item.isSelected ? 0.2 : 0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: item.isSelected ? "checkmark" : item.icon)
                    .font(.system(size: item.isSelected ? 16 : 18, weight: item.isSelected ? .bold : .regular))
                    .foregroundStyle(item.accent)
                    .transition(.scale.combined(with: .opacity))
            }
            .animation(.spring(response: 0.3), value: item.isSelected)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.body.weight(.medium))
                Text(item.description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if item.sizeBytes > 0 {
                Text(item.sizeBytes.formattedSize)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).transition(.opacity)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(item.isSelected ? item.accent.opacity(0.07) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(item.isSelected ? item.accent.opacity(0.3) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3)) { item.isSelected.toggle() } }
    }
}
