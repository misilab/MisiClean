//
//  OldFilesView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct OldFile: Identifiable {
    let id = UUID()
    let url: URL
    let sizeBytes: Int64
    let lastAccessDate: Date
    var isSelected: Bool = false

    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path }

    var ageString: String {
        let days = Int(Date().timeIntervalSince(lastAccessDate) / 86400)
        if days < 30 { return "il y a \(days) jour\(days != 1 ? "s" : "")" }
        if days < 365 { return "il y a \(days / 30) mois" }
        let years = days / 365
        return "il y a \(years) an\(years > 1 ? "s" : "")"
    }
}

enum AgeFilter: String, CaseIterable, Identifiable {
    case sixMonths = "6 mois"
    case oneYear   = "1 an"
    case twoYears  = "2 ans"

    var id: String { rawValue }

    var threshold: Date {
        let months: Int
        switch self {
        case .sixMonths: months = 6
        case .oneYear:   months = 12
        case .twoYears:  months = 24
        }
        return Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
    }
}

// MARK: - ViewModel

@MainActor
class OldFilesViewModel: ObservableObject {
    @Published var files: [OldFile] = []
    @Published var isScanning = false
    @Published var isDeleting = false
    @Published var location: ScanLocation = .downloads
    @Published var ageFilter: AgeFilter = .oneYear
    @Published var showDeleteConfirm = false
    @Published var deletedCount = 0
    @Published var showResult = false
    @Published var hasScanned = false

    var selectedFiles: [OldFile] { files.filter(\.isSelected) }
    var totalSelectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.sizeBytes } }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true; hasScanned = true; files = []
        defer { isScanning = false }
        let dir = location.url
        let threshold = ageFilter.threshold
        let result = await Task.detached(priority: .userInitiated) {
            OldFilesViewModel.findOldFiles(in: dir, before: threshold)
        }.value
        withAnimation { files = result }
    }

    func resetState() { files = []; hasScanned = false; showResult = false }

    nonisolated static func findOldFiles(in dir: URL, before threshold: Date) -> [OldFile] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .contentAccessDateKey]
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: Array(keys),
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var results: [OldFile] = []
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: keys),
                  v.isRegularFile == true,
                  let accessed = v.contentAccessDate,
                  accessed < threshold,
                  let size = v.fileSize else { continue }
            results.append(OldFile(url: url, sizeBytes: Int64(size), lastAccessDate: accessed))
        }
        return results.sorted { $0.lastAccessDate < $1.lastAccessDate }
    }

    func setSelectAll(_ value: Bool) {
        withAnimation { for i in files.indices { files[i].isSelected = value } }
    }

    func deleteSelected() async {
        guard !isDeleting else { return }
        isDeleting = true; defer { isDeleting = false }
        let toDelete = selectedFiles
        for file in toDelete { try? FileManager.default.trashItem(at: file.url, resultingItemURL: nil) }
        deletedCount = toDelete.count
        withAnimation { files.removeAll { $0.isSelected } }
        showResult = true
    }

    func revealInFinder(_ file: OldFile) {
        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
    }
}

// MARK: - Section View

struct OldFilesSection: View {
    @ObservedObject var vm: OldFilesViewModel

    var body: some View {
        VStack(spacing: 0) {
            optionsBar
            Divider()
            if vm.isScanning { scanningState }
            else if vm.files.isEmpty { emptyState }
            else { fileList; Divider(); footer }
        }
        .onChange(of: vm.location) { vm.resetState() }
        .onChange(of: vm.ageFilter) { vm.resetState() }
        .confirmationDialog(
            "Déplacer \(vm.selectedFiles.count) fichier\(vm.selectedFiles.count > 1 ? "s" : "") vers la Corbeille ?",
            isPresented: $vm.showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Déplacer vers la Corbeille", role: .destructive) { Task { await vm.deleteSelected() } }
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

    private var optionsBar: some View {
        HStack(spacing: 12) {
            Text("Non accédé depuis").font(.callout).foregroundStyle(.secondary)
            Picker("", selection: $vm.ageFilter) {
                ForEach(AgeFilter.allCases) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 200)
            Spacer()
            Picker("", selection: $vm.location) {
                ForEach(ScanLocation.allCases) { loc in Text(loc.rawValue).tag(loc) }
            }
            .frame(maxWidth: 180)
            Button { Task { await vm.scan() } } label: {
                Label(vm.isScanning ? "Analyse…" : "Analyser", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isScanning)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var scanningState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().scaleEffect(1.3)
            Text("Recherche dans \(vm.location.rawValue)…").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: vm.hasScanned ? "checkmark.circle.fill" : "calendar.badge.clock")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(vm.hasScanned ? Color.green.opacity(0.6) : Color.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text(vm.hasScanned ? "Aucun vieux fichier trouvé" : "Trouvez les fichiers dormants")
                    .font(.title3.bold())
                Text(vm.hasScanned
                     ? "Aucun fichier non accédé depuis \(vm.ageFilter.rawValue) dans « \(vm.location.rawValue) »."
                     : "Identifiez les fichiers que vous n'avez pas ouverts depuis des mois.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach($vm.files) { $file in
                    OldFileRow(file: $file) { vm.revealInFinder(file) }
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Tout sélectionner") { vm.setSelectAll(true) }
                Button("Tout désélectionner") { vm.setSelectAll(false) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).fixedSize()
            Text("\(vm.files.count) fichier\(vm.files.count > 1 ? "s" : "")")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            if vm.totalSelectedBytes > 0 {
                Text("\(vm.totalSelectedBytes.formattedSize) sélectionnés")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { vm.showDeleteConfirm = true } label: {
                Label("Corbeille", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
            .disabled(vm.selectedFiles.isEmpty || vm.isDeleting)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - File Row

struct OldFileRow: View {
    @Binding var file: OldFile
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(file.isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable().frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.body.weight(.medium)).lineLimit(1)
                Text(file.folder).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text("Dernier accès \(file.ageString)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Spacer()

            Text(file.sizeBytes.formattedSize)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: Capsule())

            Button(action: onReveal) {
                Image(systemName: "folder").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Afficher dans le Finder")
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
        .onTapGesture { withAnimation(.spring(response: 0.3)) { file.isSelected.toggle() } }
    }
}
