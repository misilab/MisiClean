//
//  DuplicatesView.swift
//  MisiClean
//

import SwiftUI
import CryptoKit
import AppKit
import Combine

// MARK: - Progress events

enum DuplicateScanEvent: Sendable {
    case fileCount(Int)
    case candidateCount(Int)
    case groupDone(Int, Int)
    case result([DuplicateGroup])
}

// MARK: - ViewModel

@MainActor
class DuplicatesViewModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var isScanning = false
    @Published var isDeleting = false
    @Published var location: ScanLocation = .downloads
    @Published var progressMessage = ""
    @Published var progressFraction: Double = 0
    @Published var showResult = false
    @Published var deletedBytes: Int64 = 0
    @Published var hasScanned = false

    var totalWasteableBytes: Int64 { groups.reduce(0) { $0 + $1.wasteableBytes } }
    var selectedBytesToDelete: Int64 { groups.reduce(0) { $0 + $1.bytesToDelete } }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        hasScanned = true
        groups = []
        progressMessage = "Énumération des fichiers…"
        progressFraction = 0
        defer { isScanning = false }

        let dir = location.url
        let (stream, cont) = AsyncStream.makeStream(of: DuplicateScanEvent.self)

        Task.detached(priority: .userInitiated) {
            DuplicatesViewModel.scanWithProgress(in: dir, continuation: cont)
        }

        for await event in stream {
            switch event {
            case .fileCount(let n):
                progressMessage = "\(n) fichiers analysés…"
            case .candidateCount(let n):
                progressFraction = 0
                progressMessage = n > 0
                    ? "Calcul SHA256 : 0 / \(n) groupes…"
                    : "Aucun doublon potentiel."
            case .groupDone(let done, let total):
                progressFraction = total > 0 ? Double(done) / Double(total) : 1
                progressMessage = "Calcul SHA256 : \(done) / \(total) groupes…"
            case .result(let found):
                withAnimation { groups = found }
                progressMessage = ""
                progressFraction = 1
            }
        }
    }

    func resetState() {
        groups = []
        hasScanned = false
        progressMessage = ""
        progressFraction = 0
    }

    // MARK: - Scan with live progress

    nonisolated static func scanWithProgress(in dir: URL, continuation cont: AsyncStream<DuplicateScanEvent>.Continuation) {
        defer { cont.finish() }

        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: Array(keys),
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return }

        // Pass 1: group by size
        var sizeMap: [Int64: [URL]] = [:]
        var fileCount = 0
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: keys),
                  v.isRegularFile == true,
                  let size = v.fileSize,
                  size >= 4096, size <= 2_000_000_000
            else { continue }
            sizeMap[Int64(size), default: []].append(url)
            fileCount += 1
            if fileCount % 500 == 0 { cont.yield(.fileCount(fileCount)) }
        }
        cont.yield(.fileCount(fileCount))

        let candidates = sizeMap.filter { $0.value.count > 1 }
        let total = candidates.count
        cont.yield(.candidateCount(total))
        guard total > 0 else { cont.yield(.result([])); return }

        // Pass 2: quick hash → full hash
        var result: [DuplicateGroup] = []
        var done = 0
        for (size, urls) in candidates {
            var quickMap: [String: [URL]] = [:]
            for url in urls {
                if let h = quickHash(url) { quickMap[h, default: []].append(url) }
            }
            for (_, qCandidates) in quickMap where qCandidates.count > 1 {
                var fullMap: [String: [URL]] = [:]
                for url in qCandidates {
                    if let h = fullHash(url) { fullMap[h, default: []].append(url) }
                }
                for (_, dupes) in fullMap where dupes.count > 1 {
                    result.append(DuplicateGroup(sizeBytes: size, files: dupes.map { DuplicateFile(url: $0) }))
                }
            }
            done += 1
            cont.yield(.groupDone(done, total))
        }
        cont.yield(.result(result.sorted { $0.wasteableBytes > $1.wasteableBytes }))
    }

    nonisolated static func quickHash(_ url: URL) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { handle.closeFile() }
        let data = handle.readData(ofLength: 65536)
        guard !data.isEmpty else { return nil }
        return Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func fullHash(_ url: URL) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { handle.closeFile() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1_048_576)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Selection

    func smartSelect() {
        withAnimation {
            for i in groups.indices {
                for j in groups[i].files.indices { groups[i].files[j].isSelected = j > 0 }
            }
        }
    }

    func clearSelection() {
        withAnimation {
            for i in groups.indices {
                for j in groups[i].files.indices { groups[i].files[j].isSelected = false }
            }
        }
    }

    // MARK: - Delete

    func deleteSelected() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        var freed: Int64 = 0
        for group in groups {
            for file in group.files where file.isSelected {
                try? FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                freed += group.sizeBytes
            }
        }
        withAnimation {
            for i in groups.indices { groups[i].files.removeAll { $0.isSelected } }
            groups.removeAll { $0.files.count < 2 }
        }
        deletedBytes = freed
        showResult = true
    }

    func revealInFinder(_ file: DuplicateFile) {
        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
    }
}

// MARK: - Section View

struct DuplicatesSection: View {
    @ObservedObject var vm: DuplicatesViewModel

    var body: some View {
        VStack(spacing: 0) {
            optionsBar
            Divider()
            if vm.isScanning { scanningState }
            else if vm.groups.isEmpty { emptyState }
            else { groupList; Divider(); footer }
        }
        .onChange(of: vm.location) { vm.resetState() }
        .alert("Fichiers déplacés", isPresented: $vm.showResult) {
            Button("OK") { }
        } message: {
            Text("\(vm.deletedBytes.formattedSize) déplacés vers la Corbeille.")
        }
    }

    private var optionsBar: some View {
        HStack(spacing: 12) {
            Text("Dossier").font(.callout).foregroundStyle(.secondary)
            Picker("", selection: $vm.location) {
                ForEach(ScanLocation.allCases) { loc in Text(loc.rawValue).tag(loc) }
            }
            .frame(maxWidth: 200)
            if vm.location == .disk {
                Label("Analyse très longue — privilèges requis", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else if vm.location == .home {
                Label("Peut prendre plusieurs minutes", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await vm.scan() } } label: {
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
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(1.3)
            Text(vm.progressMessage.isEmpty ? "Analyse en cours…" : vm.progressMessage)
                .foregroundStyle(.secondary)
                .animation(.easeInOut, value: vm.progressMessage)
            if vm.progressFraction > 0 && vm.progressFraction < 1 {
                ProgressView(value: vm.progressFraction)
                    .frame(maxWidth: 300)
                    .animation(.linear(duration: 0.2), value: vm.progressFraction)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: vm.hasScanned ? "checkmark.circle.fill" : "doc.on.doc.fill")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(vm.hasScanned ? Color.green.opacity(0.6) : Color.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text(vm.hasScanned ? "Aucun doublon trouvé" : "Rechercher des doublons")
                    .font(.title3.bold())
                Text(vm.hasScanned
                     ? "Aucun fichier en double dans « \(vm.location.rawValue) »."
                     : "Trouvez et supprimez les fichiers identiques pour libérer de l'espace.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    private var groupList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach($vm.groups) { $group in
                    DuplicateGroupCard(group: $group) { vm.revealInFinder($0) }
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(vm.groups.count) groupe\(vm.groups.count > 1 ? "s" : "") · \(vm.totalWasteableBytes.formattedSize) gaspillés")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            if vm.selectedBytesToDelete > 0 {
                Text("\(vm.selectedBytesToDelete.formattedSize) à supprimer")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary).transition(.opacity)
            }
            Button("Auto-sélectionner") { vm.smartSelect() }
                .buttonStyle(.bordered)
                .help("Garde la première copie de chaque groupe")
            Button { Task { await vm.deleteSelected() } } label: {
                Label("Corbeille", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
            .disabled(vm.selectedBytesToDelete == 0 || vm.isDeleting)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Duplicate Group Card

struct DuplicateGroupCard: View {
    @Binding var group: DuplicateGroup
    let onReveal: (DuplicateFile) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.bold()).foregroundStyle(.secondary).frame(width: 14)
                Image(systemName: "doc.on.doc.fill").foregroundStyle(.orange)
                Text("\(group.files.count) copies · \(group.sizeBytes.formattedSize) chacun")
                    .font(.body.weight(.medium))
                Spacer()
                Text("\(group.wasteableBytes.formattedSize) gaspillés")
                    .font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(.orange)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.1), in: Capsule())
            }
            .padding(10)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }

            if isExpanded {
                Divider().padding(.horizontal, 10)
                VStack(spacing: 3) {
                    ForEach($group.files) { $file in
                        DuplicateFileRow(file: $file) { onReveal(file) }
                    }
                }
                .padding(8)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(group.selectedCount > 0 ? Color.orange.opacity(0.4) : Color.clear, lineWidth: 1))
    }
}

// MARK: - Duplicate File Row

struct DuplicateFileRow: View {
    @Binding var file: DuplicateFile
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.body).foregroundStyle(file.isSelected ? .orange : .secondary).frame(width: 20)
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(file.folder).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button(action: onReveal) {
                Image(systemName: "folder").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Afficher dans le Finder")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(file.isSelected ? Color.orange.opacity(0.08) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3)) { file.isSelected.toggle() } }
    }
}
