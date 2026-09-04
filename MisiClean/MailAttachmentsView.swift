//
//  MailAttachmentsView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct MailAttachmentFolder: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let sizeBytes: Int64
    var isSelected: Bool = false
}

// MARK: - ViewModel

@MainActor
class MailAttachmentsViewModel: ObservableObject {
    @Published var folders: [MailAttachmentFolder] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var isDeleting = false
    @Published var showDeleteConfirm = false
    @Published var showResult = false
    @Published var freedBytes: Int64 = 0

    var selected: [MailAttachmentFolder] { folders.filter(\.isSelected) }
    var totalSelectedBytes: Int64 { selected.reduce(0) { $0 + $1.sizeBytes } }
    var totalBytes: Int64 { folders.reduce(0) { $0 + $1.sizeBytes } }

    func scan() async {
        isScanning = true; hasScanned = true
        defer { isScanning = false }
        let result = await Task.detached(priority: .userInitiated) {
            MailAttachmentsViewModel.findAttachments()
        }.value
        withAnimation { folders = result }
    }

    func setSelectAll(_ value: Bool) {
        for i in folders.indices { folders[i].isSelected = value }
    }

    func deleteSelected() async {
        guard !isDeleting else { return }
        isDeleting = true; defer { isDeleting = false }
        var freed: Int64 = 0
        let toDelete = selected
        for f in toDelete {
            freed += f.sizeBytes
            try? FileManager.default.trashItem(at: f.url, resultingItemURL: nil)
        }
        freedBytes = freed
        let deleted = Set(toDelete.map { $0.url.path })
        withAnimation { folders.removeAll { deleted.contains($0.url.path) } }
        showResult = true
    }

    func reveal(_ f: MailAttachmentFolder) {
        NSWorkspace.shared.activateFileViewerSelecting([f.url])
    }

    nonisolated static func findAttachments() -> [MailAttachmentFolder] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var results: [MailAttachmentFolder] = []

        // ~/Library/Mail/V* variants
        let mailBase = home.appendingPathComponent("Library/Mail")
        if let versions = try? fm.contentsOfDirectory(at: mailBase, includingPropertiesForKeys: nil) {
            for ver in versions where ver.lastPathComponent.hasPrefix("V") {
                let attachDir = ver.appendingPathComponent("Attachments")
                if fm.fileExists(atPath: attachDir.path) {
                    if let subs = try? fm.contentsOfDirectory(at: attachDir, includingPropertiesForKeys: nil) {
                        for sub in subs {
                            let size = dirSize(at: sub)
                            if size > 0 {
                                results.append(MailAttachmentFolder(
                                    url: sub,
                                    name: sub.lastPathComponent,
                                    sizeBytes: size))
                            }
                        }
                    }
                }
            }
        }

        // ~/Library/Containers/com.apple.mail
        let containerMail = home.appendingPathComponent("Library/Containers/com.apple.mail")
        if fm.fileExists(atPath: containerMail.path) {
            let attachPath = containerMail.appendingPathComponent("Data/Library/Mail Downloads")
            if fm.fileExists(atPath: attachPath.path) {
                let size = dirSize(at: attachPath)
                if size > 0 {
                    results.append(MailAttachmentFolder(
                        url: attachPath,
                        name: "Mail Downloads (Sandbox)",
                        sizeBytes: size))
                }
            }
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    nonisolated private static func dirSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                    options: [.skipsHiddenFiles]) else { return 0 }
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

struct MailAttachmentsSection: View {
    @ObservedObject var vm: MailAttachmentsViewModel
    private let accent = Color(red: 0.1, green: 0.55, blue: 0.9)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isScanning { loadingState }
            else if !vm.hasScanned { idleState }
            else if vm.folders.isEmpty { emptyState }
            else { folderList; Divider(); footer }
        }
        .onAppear { Task { await vm.scan() } }
        .confirmationDialog(
            "Déplacer \(vm.selected.count) dossier\(vm.selected.count > 1 ? "s" : "") vers la Corbeille ?",
            isPresented: $vm.showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Déplacer vers la Corbeille", role: .destructive) { Task { await vm.deleteSelected() } }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("\(vm.totalSelectedBytes.formattedSize) de pièces jointes seront supprimées. Mail les re-téléchargera si besoin.")
        }
        .alert("Nettoyage terminé", isPresented: $vm.showResult) { Button("OK") { } } message: {
            Text("\(vm.freedBytes.formattedSize) de pièces jointes déplacées vers la Corbeille.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pièces jointes Mail").font(.callout.weight(.semibold))
                Text("Pièces jointes Mail stockées localement · \(vm.totalBytes.formattedSize)")
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
            Text("Analyse des pièces jointes Mail…").foregroundStyle(.secondary); Spacer() }
    }

    private var idleState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 60, weight: .thin)).foregroundStyle(accent.opacity(0.6))
            VStack(spacing: 6) {
                Text("Pièces jointes Mail").font(.title3.bold())
                Text("Mail conserve une copie locale de toutes les pièces jointes. Elles peuvent peser plusieurs dizaines de Go.")
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
                Text("Aucune pièce jointe trouvée").font(.title3.bold())
                Text("Votre dossier Mail ne contient pas de pièces jointes locales détectables.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }.padding(32)
    }

    private var folderList: some View {
        ScrollView {
            VStack(spacing: 10) {
                infoCard
                LazyVStack(spacing: 5) {
                    ForEach($vm.folders) { $f in
                        MailFolderRow(folder: $f, accent: accent) { vm.reveal(f) }
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
                Text("Sécurité de suppression").font(.callout.weight(.medium))
                Text("Mail re-télécharge automatiquement les pièces jointes depuis le serveur si vous les ouvrez à nouveau. La suppression est sans risque.")
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
            Text("\(vm.folders.count) dossier\(vm.folders.count > 1 ? "s" : "") · \(vm.totalBytes.formattedSize)")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
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

struct MailFolderRow: View {
    @Binding var folder: MailAttachmentFolder
    let accent: Color
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: folder.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(folder.isSelected ? accent : Color.secondary)
                .frame(width: 24)

            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.1)).frame(width: 36, height: 36)
                Image(systemName: "paperclip").font(.system(size: 15)).foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name).font(.body.weight(.medium)).lineLimit(1)
                Text(folder.url.deletingLastPathComponent().path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }

            Spacer()

            Text(folder.sizeBytes.formattedSize)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(folder.sizeBytes > 1_000_000_000 ? .red :
                                 folder.sizeBytes > 200_000_000 ? .orange : .secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08), in: Capsule())

            Button(action: onReveal) {
                Image(systemName: "folder").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Afficher dans le Finder")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(folder.isSelected ? accent.opacity(0.07) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(folder.isSelected ? accent.opacity(0.3) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3)) { folder.isSelected.toggle() } }
    }
}
