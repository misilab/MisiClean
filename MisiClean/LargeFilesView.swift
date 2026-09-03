//
//  LargeFilesView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - ViewModel

@MainActor
class LargeFilesViewModel: ObservableObject {
    @Published var files: [LargeFile] = []
    @Published var isScanning = false
    @Published var isDeleting = false
    @Published var location: ScanLocation = .downloads
    @Published var minSizeMB: Int = 100
    @Published var showDeleteConfirm = false
    @Published var deletedCount = 0
    @Published var showResult = false
    @Published var hasScanned = false

    let sizeOptions = [50, 100, 250, 500, 1000]

    var selectedFiles: [LargeFile] { files.filter(\.isSelected) }
    var totalSelectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.sizeBytes } }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        hasScanned = true
        files = []
        defer { isScanning = false }

        let dir = location.url
        let minBytes = Int64(minSizeMB) * 1_000_000
        let result = await Task.detached(priority: .userInitiated) {
            LargeFilesViewModel.findLargeFiles(in: dir, minBytes: minBytes)
        }.value
        withAnimation { files = result }
    }

    func resetState() {
        files = []
        hasScanned = false
        showResult = false
    }

    nonisolated static func findLargeFiles(in dir: URL, minBytes: Int64) -> [LargeFile] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .contentAccessDateKey]
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: Array(keys),
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var results: [LargeFile] = []
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: keys),
                  v.isRegularFile == true,
                  let size = v.fileSize,
                  Int64(size) >= minBytes else { continue }
            results.append(LargeFile(url: url, sizeBytes: Int64(size), lastAccessedDate: v.contentAccessDate))
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    func setSelectAll(_ value: Bool) {
        withAnimation { for i in files.indices { files[i].isSelected = value } }
    }

    func deleteSelected() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        let toDelete = selectedFiles
        for file in toDelete {
            try? FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
        }
        deletedCount = toDelete.count
        withAnimation { files.removeAll { $0.isSelected } }
        showResult = true
    }

    func revealInFinder(_ file: LargeFile) {
        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
    }
}

// MARK: - Section View

struct LargeFilesSection: View {
    @ObservedObject var vm: LargeFilesViewModel

    var body: some View {
        VStack(spacing: 0) {
            optionsBar
            Divider()

            if vm.isScanning {
                scanningState
            } else if vm.files.isEmpty {
                emptyState
            } else {
                fileList
                Divider()
                footer
            }
        }
        .onChange(of: vm.location) { vm.resetState() }
        .onChange(of: vm.minSizeMB) { vm.resetState() }
        .confirmationDialog(
            "Déplacer \(vm.selectedFiles.count) fichier\(vm.selectedFiles.count > 1 ? "s" : "") vers la Corbeille ?",
            isPresented: $vm.showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Déplacer vers la Corbeille", role: .destructive) {
                Task { await vm.deleteSelected() }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("\(vm.totalSelectedBytes.formattedSize) seront déplacés vers la Corbeille.")
        }
        .alert("Fichiers déplacés", isPresented: $vm.showResult) {
            Button("OK") { }
        } message: {
            Text("\(vm.deletedCount) fichier\(vm.deletedCount > 1 ? "s" : "") déplacé\(vm.deletedCount > 1 ? "s" : "") vers la Corbeille.")
        }
    }

    // MARK: Options bar

    private var optionsBar: some View {
        HStack(spacing: 12) {
            Text("Taille min.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("", selection: $vm.minSizeMB) {
                ForEach(vm.sizeOptions, id: \.self) { size in
                    Text(size < 1000 ? "\(size) Mo" : "\(size / 1000) Go").tag(size)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            Spacer()

            Picker("", selection: $vm.location) {
                ForEach(ScanLocation.allCases) { loc in Text(loc.rawValue).tag(loc) }
            }
            .frame(maxWidth: 180)

            Button {
                Task { await vm.scan() }
            } label: {
                Label(vm.isScanning ? "Analyse…" : "Analyser", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isScanning)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: States

    private var scanningState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().scaleEffect(1.3)
            Text("Recherche dans \(vm.location.rawValue)…")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: vm.hasScanned ? "checkmark.circle.fill" : "doc.fill.badge.ellipsis")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(vm.hasScanned ? Color.green.opacity(0.6) : Color.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text(vm.hasScanned ? "Aucun gros fichier trouvé" : "Analysez vos fichiers")
                    .font(.title3.bold())
                Text(vm.hasScanned
                     ? "Aucun fichier de plus de \(vm.minSizeMB < 1000 ? "\(vm.minSizeMB) Mo" : "\(vm.minSizeMB/1000) Go") dans \"\(vm.location.rawValue)\"."
                     : "Trouvez les fichiers qui prennent le plus de place sur votre disque.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: File list

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach($vm.files) { $file in
                    LargeFileRow(file: $file) { vm.revealInFinder(file) }
                }
            }
            .padding(12)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Tout sélectionner") { vm.setSelectAll(true) }
                Button("Tout désélectionner") { vm.setSelectAll(false) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text("\(vm.files.count) fichier\(vm.files.count > 1 ? "s" : "") · \(vm.files.reduce(0) { $0 + $1.sizeBytes }.formattedSize) au total")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            if vm.totalSelectedBytes > 0 {
                Text("\(vm.totalSelectedBytes.formattedSize) sélectionnés")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                vm.showDeleteConfirm = true
            } label: {
                Label("Corbeille", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            .disabled(vm.selectedFiles.isEmpty || vm.isDeleting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - File Row

struct LargeFileRow: View {
    @Binding var file: LargeFile
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(file.isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(file.folder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let date = file.lastAccessedDate {
                    Text("Dernier accès \(date.relativeFormatted)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(file.sizeBytes.formattedSize)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(file.sizeBytes > 1_000_000_000 ? .red : .orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    (file.sizeBytes > 1_000_000_000 ? Color.red : Color.orange).opacity(0.1),
                    in: Capsule()
                )

            Button(action: onReveal) {
                Image(systemName: "folder").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Afficher dans le Finder")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(file.isSelected ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(file.isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) { file.isSelected.toggle() }
        }
    }
}
