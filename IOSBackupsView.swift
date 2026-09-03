//
//  IOSBackupsView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct IOSBackup: Identifiable {
    let id = UUID()
    let folderURL: URL
    let deviceName: String
    let iosVersion: String
    let backupDate: Date?
    let sizeBytes: Int64
    var isSelected: Bool = false

    var formattedDate: String {
        guard let d = backupDate else { return "Date inconnue" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: d)
    }

    var ageString: String {
        guard let d = backupDate else { return "" }
        let days = Int(Date().timeIntervalSince(d) / 86400)
        if days == 0 { return "aujourd'hui" }
        if days == 1 { return "hier" }
        if days < 30 { return "il y a \(days) jour\(days > 1 ? "s" : "")" }
        if days < 365 { return "il y a \(days / 30) mois" }
        return "il y a \(days / 365) an\(days / 365 > 1 ? "s" : "")"
    }
}

// MARK: - ViewModel

@MainActor
class IOSBackupsViewModel: ObservableObject {
    @Published var backups: [IOSBackup] = []
    @Published var isLoading = false
    @Published var isDeleting = false
    @Published var hasLoaded = false
    @Published var showDeleteConfirm = false
    @Published var showResult = false
    @Published var freedBytes: Int64 = 0

    var selected: [IOSBackup] { backups.filter(\.isSelected) }
    var totalSelectedBytes: Int64 { selected.reduce(0) { $0 + $1.sizeBytes } }
    var totalBytes: Int64 { backups.reduce(0) { $0 + $1.sizeBytes } }

    func load() async {
        isLoading = true; hasLoaded = true
        defer { isLoading = false }
        let result = await Task.detached(priority: .userInitiated) {
            IOSBackupsViewModel.findBackups()
        }.value
        withAnimation { backups = result }
    }

    func setSelectAll(_ value: Bool) {
        withAnimation { for i in backups.indices { backups[i].isSelected = value } }
    }

    func deleteSelected() async {
        guard !isDeleting else { return }
        isDeleting = true; defer { isDeleting = false }
        var freed: Int64 = 0
        let toDelete = selected
        for backup in toDelete {
            freed += backup.sizeBytes
            try? FileManager.default.trashItem(at: backup.folderURL, resultingItemURL: nil)
        }
        let deletedPaths = Set(toDelete.map { $0.folderURL.path })
        freedBytes = freed
        withAnimation { backups.removeAll { deletedPaths.contains($0.folderURL.path) } }
        showResult = true
    }

    nonisolated static func findBackups() -> [IOSBackup] {
        let fm = FileManager.default
        let backupDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MobileSync/Backup")
        guard let entries = try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil) else { return [] }

        return entries.compactMap { url -> IOSBackup? in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }

            let infoPlist = url.appendingPathComponent("Info.plist")
            var deviceName = "Appareil iOS"
            var iosVersion = ""
            var backupDate: Date? = nil

            if let data = try? Data(contentsOf: infoPlist),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                deviceName = plist["Device Name"]      as? String ?? "Appareil iOS"
                iosVersion = plist["Product Version"]  as? String ?? ""
                backupDate = plist["Last Backup Date"] as? Date
            }

            if backupDate == nil {
                backupDate = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            }

            let size = dirSize(at: url)
            guard size > 0 else { return nil }
            return IOSBackup(
                folderURL: url, deviceName: deviceName,
                iosVersion: iosVersion, backupDate: backupDate, sizeBytes: size)
        }
        .sorted { ($0.backupDate ?? .distantPast) > ($1.backupDate ?? .distantPast) }
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

struct IOSBackupsSection: View {
    @ObservedObject var vm: IOSBackupsViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isLoading || !vm.hasLoaded { loadingState }
            else if vm.backups.isEmpty { emptyState }
            else { backupList; Divider(); footer }
        }
        .onAppear { Task { await vm.load() } }
        .confirmationDialog(
            "Déplacer \(vm.selected.count) sauvegarde\(vm.selected.count > 1 ? "s" : "") vers la Corbeille ?",
            isPresented: $vm.showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Déplacer vers la Corbeille", role: .destructive) { Task { await vm.deleteSelected() } }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("\(vm.totalSelectedBytes.formattedSize) seront déplacés vers la Corbeille.")
        }
        .alert("Sauvegardes supprimées", isPresented: $vm.showResult) { Button("OK") { } } message: {
            Text("\(vm.freedBytes.formattedSize) libérés.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sauvegardes iOS").font(.callout.weight(.semibold))
                Text("Sauvegardes iPhone/iPad via Finder — \(vm.backups.count) trouvée\(vm.backups.count != 1 ? "s" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
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
        VStack(spacing: 14) {
            Spacer()
            ProgressView().scaleEffect(1.3)
            Text("Recherche des sauvegardes…").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "iphone")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(Color.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text("Aucune sauvegarde locale").font(.title3.bold())
                Text("Connectez votre iPhone ou iPad et sauvegardez-le via Finder pour créer une sauvegarde locale.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(32)
    }

    private var backupList: some View {
        ScrollView {
            VStack(spacing: 0) {
                infoCard
                    .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
                LazyVStack(spacing: 5) {
                    ForEach($vm.backups) { $backup in
                        IOSBackupRow(backup: $backup)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }

    private var infoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill").foregroundStyle(.secondary).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sauvegardes locales").font(.callout.weight(.medium))
                Text("Chaque sauvegarde peut peser 5 à 50 Go. Conservez uniquement la plus récente par appareil.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
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
            Text("\(vm.backups.count) sauvegarde\(vm.backups.count > 1 ? "s" : "") · \(vm.totalBytes.formattedSize)")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            if vm.isDeleting {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.75)
                    Text("Suppression…").font(.callout).foregroundStyle(.secondary)
                }
            }
            if vm.totalSelectedBytes > 0 {
                Text("\(vm.totalSelectedBytes.formattedSize) sélectionnés")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { vm.showDeleteConfirm = true } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.3, green: 0.5, blue: 0.9))
            .controlSize(.large)
            .disabled(vm.selected.isEmpty || vm.isDeleting)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Backup Row

struct IOSBackupRow: View {
    @Binding var backup: IOSBackup
    private let accent = Color(red: 0.3, green: 0.5, blue: 0.9)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: backup.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(backup.isSelected ? accent : Color.secondary)
                .frame(width: 24)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accent.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "iphone")
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(backup.deviceName).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if !backup.iosVersion.isEmpty {
                        Text("iOS \(backup.iosVersion)")
                            .font(.caption).foregroundStyle(accent)
                    }
                    Text(backup.formattedDate)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(backup.sizeBytes.formattedSize)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(backup.sizeBytes > 10_000_000_000 ? .red :
                                     backup.sizeBytes > 5_000_000_000 ? .orange : .primary)
                if !backup.ageString.isEmpty {
                    Text(backup.ageString).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(backup.isSelected ? accent.opacity(0.07) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(backup.isSelected ? accent.opacity(0.3) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3)) { backup.isSelected.toggle() } }
    }
}
