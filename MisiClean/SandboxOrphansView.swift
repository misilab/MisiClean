//
//  SandboxOrphansView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct SandboxOrphan: Identifiable {
    let id = UUID()
    let url: URL
    let bundleID: String
    let sizeBytes: Int64
    var isSelected: Bool = false
    var isGroupContainer: Bool = false

    var displayName: String { bundleID }
}

// MARK: - ViewModel

@MainActor
class SandboxOrphansViewModel: ObservableObject {
    @Published var orphans: [SandboxOrphan] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var isDeleting = false
    @Published var showDeleteConfirm = false
    @Published var showResult = false
    @Published var freedBytes: Int64 = 0

    var selected: [SandboxOrphan] { orphans.filter(\.isSelected) }
    var totalSelectedBytes: Int64 { selected.reduce(0) { $0 + $1.sizeBytes } }
    var totalBytes: Int64 { orphans.reduce(0) { $0 + $1.sizeBytes } }

    func scan() async {
        isScanning = true; hasScanned = true
        defer { isScanning = false }
        let result = await Task.detached(priority: .userInitiated) {
            SandboxOrphansViewModel.findOrphans()
        }.value
        withAnimation { orphans = result }
    }

    func setSelectAll(_ value: Bool) {
        for i in orphans.indices { orphans[i].isSelected = value }
    }

    func deleteSelected() async {
        guard !isDeleting else { return }
        isDeleting = true; defer { isDeleting = false }
        var freed: Int64 = 0
        let toDelete = selected
        for o in toDelete {
            freed += o.sizeBytes
            try? FileManager.default.trashItem(at: o.url, resultingItemURL: nil)
        }
        freedBytes = freed
        let deleted = Set(toDelete.map { $0.url.path })
        withAnimation { orphans.removeAll { deleted.contains($0.url.path) } }
        showResult = true
    }

    func reveal(_ o: SandboxOrphan) {
        NSWorkspace.shared.activateFileViewerSelecting([o.url])
    }

    nonisolated static func findOrphans() -> [SandboxOrphan] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var results: [SandboxOrphan] = []

        // Installed app bundle IDs
        let installedBundleIDs = installedAppBundleIDs()

        // ~/Library/Containers/
        let containers = home.appendingPathComponent("Library/Containers")
        if let entries = try? fm.contentsOfDirectory(at: containers, includingPropertiesForKeys: nil) {
            for entry in entries {
                let bundleID = entry.lastPathComponent
                guard !isSystemBundle(bundleID) else { continue }
                guard !installedBundleIDs.contains(bundleID) else { continue }
                let size = dirSize(at: entry)
                if size > 1_000_000 { // > 1 Mo seulement
                    results.append(SandboxOrphan(
                        url: entry, bundleID: bundleID,
                        sizeBytes: size, isGroupContainer: false))
                }
            }
        }

        // ~/Library/Group Containers/
        let groupContainers = home.appendingPathComponent("Library/Group Containers")
        if let entries = try? fm.contentsOfDirectory(at: groupContainers, includingPropertiesForKeys: nil) {
            for entry in entries {
                let name = entry.lastPathComponent
                // Extract bundle-like ID (e.g., "group.com.foo.bar" → "com.foo.bar")
                let bundleID = name.hasPrefix("group.") ? String(name.dropFirst(6)) : name
                guard !isSystemBundle(bundleID) && !isSystemBundle(name) else { continue }
                // Check if the base domain matches any installed app
                let baseDomain = bundleID.components(separatedBy: ".").prefix(3).joined(separator: ".")
                let matched = installedBundleIDs.contains { $0.hasPrefix(baseDomain) }
                guard !matched else { continue }
                let size = dirSize(at: entry)
                if size > 1_000_000 {
                    results.append(SandboxOrphan(
                        url: entry, bundleID: name,
                        sizeBytes: size, isGroupContainer: true))
                }
            }
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    nonisolated private static func installedAppBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let fm = FileManager.default
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        for dir in appDirs {
            guard let apps = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for app in apps where app.pathExtension == "app" {
                let infoPlist = app.appendingPathComponent("Contents/Info.plist")
                if let data = try? Data(contentsOf: infoPlist),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let bid = plist["CFBundleIdentifier"] as? String {
                    ids.insert(bid)
                }
            }
        }
        return ids
    }

    nonisolated private static func isSystemBundle(_ id: String) -> Bool {
        let systemPrefixes = ["com.apple.", "com.microsoft.", "com.google.", "io.apple.",
                              "com.adobe.", "com.charlesoft.", "apple."]
        return systemPrefixes.contains { id.hasPrefix($0) }
    }

    nonisolated static func dirSize(at url: URL) -> Int64 {
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

struct SandboxOrphansSection: View {
    @ObservedObject var vm: SandboxOrphansViewModel
    private let accent = Color(red: 0.5, green: 0.35, blue: 0.85)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isScanning { loadingState }
            else if !vm.hasScanned { idleState }
            else if vm.orphans.isEmpty { emptyState }
            else { orphanList; Divider(); footer }
        }
        .onAppear { Task { await vm.scan() } }
        .confirmationDialog(
            "Déplacer \(vm.selected.count) conteneur\(vm.selected.count > 1 ? "s" : "") vers la Corbeille ?",
            isPresented: $vm.showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Déplacer vers la Corbeille", role: .destructive) { Task { await vm.deleteSelected() } }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Ces données appartiennent à des apps désinstallées. Elles ne seront plus utilisées.")
        }
        .alert("Nettoyage terminé", isPresented: $vm.showResult) { Button("OK") { } } message: {
            Text("\(vm.freedBytes.formattedSize) de données sandbox libérés.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Données sandbox orphelines").font(.callout.weight(.semibold))
                Text("Données d'apps Mac App Store désinstallées · \(vm.totalBytes.formattedSize)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isScanning { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.scan() } } label: {
                Label("Analyser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered).disabled(vm.isScanning)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var loadingState: some View {
        VStack(spacing: 14) { Spacer(); ProgressView().scaleEffect(1.3)
            Text("Analyse des conteneurs sandbox…").foregroundStyle(.secondary); Spacer() }
    }

    private var idleState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 60, weight: .thin)).foregroundStyle(accent.opacity(0.6))
            VStack(spacing: 6) {
                Text("Conteneurs sandbox orphelins").font(.title3.bold())
                Text("Quand vous désinstallez une app Mac App Store, ses données restent dans ~/Library/Containers.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }.padding(32)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60, weight: .thin)).foregroundStyle(Color.green.opacity(0.6))
            VStack(spacing: 6) {
                Text("Aucun orphelin détecté").font(.title3.bold())
                Text("Tous les conteneurs sandbox correspondent à des apps installées.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }.padding(32)
    }

    private var orphanList: some View {
        ScrollView {
            VStack(spacing: 10) {
                infoCard
                LazyVStack(spacing: 5) {
                    ForEach($vm.orphans) { $o in
                        SandboxOrphanRow(orphan: $o, accent: accent) { vm.reveal(o) }
                    }
                }
            }
            .padding(12)
        }
    }

    private var infoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill").foregroundStyle(accent).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Seules les apps non-système sont listées").font(.callout.weight(.medium))
                Text("Les conteneurs Apple, Google, Microsoft sont exclus. Vérifiez avant de supprimer si vous avez désinstallé récemment.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Tout sélectionner")   { vm.setSelectAll(true) }
                Button("Tout désélectionner") { vm.setSelectAll(false) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).fixedSize()
            Text("\(vm.orphans.count) orphelin\(vm.orphans.count > 1 ? "s" : "") · \(vm.totalBytes.formattedSize)")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            if vm.isDeleting { ProgressView().scaleEffect(0.75) }
            if vm.totalSelectedBytes > 0 {
                Text("\(vm.totalSelectedBytes.formattedSize)").font(.callout.monospacedDigit().weight(.semibold))
            }
            Button { vm.showDeleteConfirm = true } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
            .disabled(vm.selected.isEmpty || vm.isDeleting)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

struct SandboxOrphanRow: View {
    @Binding var orphan: SandboxOrphan
    let accent: Color
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: orphan.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(orphan.isSelected ? accent : Color.secondary)
                .frame(width: 24)

            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.1)).frame(width: 36, height: 36)
                Image(systemName: orphan.isGroupContainer ? "square.3.layers.3d" : "shippingbox.fill")
                    .font(.system(size: 14)).foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(orphan.displayName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1)
                Text(orphan.isGroupContainer ? "Group Container" : "Conteneur App Sandbox")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text(orphan.sizeBytes.formattedSize)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(orphan.sizeBytes > 500_000_000 ? .red :
                                 orphan.sizeBytes > 100_000_000 ? .orange : .secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08), in: Capsule())

            Button(action: onReveal) {
                Image(systemName: "folder").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Afficher dans le Finder")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(orphan.isSelected ? accent.opacity(0.07) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(orphan.isSelected ? accent.opacity(0.3) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3)) { orphan.isSelected.toggle() } }
    }
}
