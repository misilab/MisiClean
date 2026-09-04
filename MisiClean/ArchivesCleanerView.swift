import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct StaleFile: Identifiable {
    let id = UUID()
    let url: URL
    let sizeBytes: Int64
    let modifiedDate: Date
    let category: StaleCategory
    var isSelected: Bool = false

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    var name: String { url.lastPathComponent }
    var folderDisplay: String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: Self.home, with: "~")
    }
}

enum StaleCategory: String, CaseIterable {
    case archive   = "Archive"
    case screenshot = "Capture d'écran"
    case vmDisk    = "Disque VM"
}

// MARK: - ViewModel

@MainActor
final class ArchivesViewModel: ObservableObject {
    @Published var files: [StaleFile] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var activeTab: StaleCategory = .archive

    var filteredFiles: [StaleFile] {
        files.filter { $0.category == activeTab }
             .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    var totalSelectedBytes: Int64 {
        files.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeBytes }
    }

    func scan() async {
        isScanning = true
        files = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // nonisolated helpers → child tasks run off @MainActor concurrently
        async let archives    = Task.detached(priority: .userInitiated) { self.scanArchives(home: home, fm: fm) }.value
        async let screenshots = Task.detached(priority: .userInitiated) { self.scanScreenshots(home: home, fm: fm) }.value
        async let vms         = Task.detached(priority: .userInitiated) { self.scanVMDisks(home: home, fm: fm) }.value

        let results = await archives + screenshots + vms
        files = results
        isScanning = false
        hasScanned = true
    }

    func deleteSelected() async {
        let fm = FileManager.default
        var remaining: [StaleFile] = []
        for file in files {
            if file.isSelected {
                try? fm.trashItem(at: file.url, resultingItemURL: nil)
            } else {
                remaining.append(file)
            }
        }
        files = remaining
    }

    func toggleSelection(id: UUID) {
        if let idx = files.firstIndex(where: { $0.id == id }) {
            files[idx].isSelected.toggle()
        }
    }

    // MARK: - Scan helpers (nonisolated → run off @MainActor for true concurrency via async let)

    nonisolated private func scanArchives(home: URL, fm: FileManager) -> [StaleFile] {
        let exts: Set<String> = ["dmg","pkg","zip","tar","gz","tgz","bz2","rar","7z","xz","zst"]
        let roots = [home.appendingPathComponent("Downloads"),
                     home.appendingPathComponent("Desktop"),
                     home.appendingPathComponent("Documents")]
        return Self.collectFiles(roots: roots, extensions: exts, maxDepth: 3, category: .archive, fm: fm)
    }

    nonisolated private func scanScreenshots(home: URL, fm: FileManager) -> [StaleFile] {
        let exts: Set<String> = ["png","jpg","jpeg"]
        var roots = [home.appendingPathComponent("Desktop")]
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !custom.isEmpty {
            roots.append(URL(fileURLWithPath: custom))
        }
        let keywords = ["Capture d'écran", "Screenshot", "Screen Shot"]
        return Self.collectFiles(roots: roots, extensions: exts, maxDepth: 2, category: .screenshot, fm: fm) { url in
            let name = url.lastPathComponent
            return keywords.contains(where: { name.contains($0) })
        }
    }

    nonisolated private func scanVMDisks(home: URL, fm: FileManager) -> [StaleFile] {
        let exts: Set<String> = ["vmdk","vmx","vdi","vhd","vhdx","qcow2","qcow","hdd","hds"]
        let roots = [
            home.appendingPathComponent("Parallels"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Virtual Machines.localized"),
            home.appendingPathComponent("VirtualBox VMs"),
            home.appendingPathComponent("Library/Containers/com.utmapp.UTM/Data/Documents")
        ]
        return Self.collectFiles(roots: roots, extensions: exts, maxDepth: 4, category: .vmDisk, fm: fm)
    }

    nonisolated private static func collectFiles(roots: [URL],
                              extensions: Set<String>,
                              maxDepth: Int,
                              category: StaleCategory,
                              fm: FileManager,
                              filter: ((URL) -> Bool)? = nil) -> [StaleFile] {
        var results: [StaleFile] = []
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            let rootComponents = root.pathComponents.count
            guard let enumerator = fm.enumerator(at: root,
                                                  includingPropertiesForKeys: keys,
                                                  options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                let depth = url.pathComponents.count - rootComponents
                if depth > maxDepth { enumerator.skipDescendants(); continue }
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                if let f = filter, !f(url) { continue }
                guard let vals = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                let isDir = vals.isDirectory ?? false
                let size: Int64 = isDir
                    ? measureFolderStatic(url, fm: fm)
                    : Int64(vals.fileSize ?? 0)
                let modDate = vals.contentModificationDate ?? Date.distantPast
                results.append(StaleFile(url: url, sizeBytes: size, modifiedDate: modDate, category: category))
            }
        }
        return results
    }

    nonisolated private static func measureFolderStatic(_ url: URL, fm: FileManager) -> Int64 {
        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: url,
                                          includingPropertiesForKeys: [.fileSizeKey],
                                          options: [.skipsHiddenFiles]) {
            for case let file as URL in enumerator {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }
}

// MARK: - Main View

struct ArchivesSection: View {
    @ObservedObject var vm: ArchivesViewModel

    private func accent(for cat: StaleCategory) -> Color {
        switch cat {
        case .archive:    return Color(red: 0.6,  green: 0.45, blue: 0.2)
        case .screenshot: return Color(red: 0.3,  green: 0.5,  blue: 0.9)
        case .vmDisk:     return Color(red: 0.7,  green: 0.15, blue: 0.75)
        }
    }

    private func icon(for cat: StaleCategory) -> String {
        switch cat {
        case .archive:    return "archivebox.fill"
        case .screenshot: return "camera.fill"
        case .vmDisk:     return "externaldrive.fill"
        }
    }

    private var currentAccent: Color { accent(for: vm.activeTab) }

    private var subtitle: String {
        let filtered = vm.filteredFiles
        let count = filtered.count
        let totalBytes = filtered.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return "\(count) fichier\(count == 1 ? "" : "s") · \(totalBytes.formattedSize)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Archives & Nettoyage")
                            .font(.title2).bold()
                        if vm.hasScanned {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await vm.scan() }
                    } label: {
                        Label("Scanner", systemImage: "magnifyingglass")
                    }
                    .disabled(vm.isScanning)
                }

                if vm.hasScanned || vm.isScanning {
                    Picker("", selection: $vm.activeTab) {
                        ForEach(StaleCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: icon(for: cat)).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            // Body
            if vm.isScanning {
                scanningView
            } else if !vm.hasScanned {
                emptyStateView
            } else {
                resultView
            }
        }
    }

    // MARK: States

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "archivebox.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Archives, captures et disques VM")
                .font(.title3).bold()
            Text("Détectez les archives volumineuses, captures d'écran accumulées et disques de machines virtuelles pour libérer de l'espace.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                Task { await vm.scan() }
            } label: {
                Label("Scanner", systemImage: "magnifyingglass")
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
            Text("Analyse en cours…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultView: some View {
        VStack(spacing: 0) {
            if vm.filteredFiles.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: icon(for: vm.activeTab))
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Aucun fichier trouvé dans cette catégorie.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.filteredFiles) { file in
                        StaleFileRow(file: file, accent: currentAccent, icon: icon(for: vm.activeTab)) {
                            vm.toggleSelection(id: file.id)
                        }
                    }
                }
                .listStyle(.inset)

                Divider()
                footer
            }
        }
    }

    private var footer: some View {
        HStack {
            let selectedCount = vm.files.filter { $0.isSelected }.count
            if selectedCount > 0 {
                Text("\(selectedCount) sélectionné\(selectedCount > 1 ? "s" : "") · \(vm.totalSelectedBytes.formattedSize)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Sélectionnez des fichiers à supprimer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                Task { await vm.deleteSelected() }
            } label: {
                Label("Mettre à la Corbeille", systemImage: "trash")
            }
            .disabled(vm.totalSelectedBytes == 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Row

private struct StaleFileRow: View {
    let file: StaleFile
    let accent: Color
    let icon: String
    let onToggle: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.callout).bold()
                    .lineLimit(1)
                Text(file.folderDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(Self.dateFormatter.string(from: file.modifiedDate))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(file.sizeBytes.formattedSize)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Image(systemName: file.isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(file.isSelected ? accent : .secondary)
                .font(.title3)
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .padding(.vertical, 4)
    }
}
