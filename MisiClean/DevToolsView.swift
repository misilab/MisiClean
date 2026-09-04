//
//  DevToolsView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct DevCategory: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let accent: Color
    let paths: [String]
    var sizeBytes: Int64 = 0
    var fileCount: Int = 0
    var isSelected: Bool = false
    var isScanning: Bool = false
}

// MARK: - ViewModel

@MainActor
class DevToolsViewModel: ObservableObject {
    @Published var categories: [DevCategory] = []
    @Published var isScanning = false
    @Published var isDeleting = false
    @Published var hasScanned = false
    @Published var showDeleteConfirm = false
    @Published var showResult = false
    @Published var freedBytes: Int64 = 0

    var selected: [DevCategory] { categories.filter(\.isSelected) }
    var totalSelectedBytes: Int64 { selected.reduce(0) { $0 + $1.sizeBytes } }

    init() {
        categories = Self.buildCategories()
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true; hasScanned = true
        defer { isScanning = false }

        for i in categories.indices { categories[i].isScanning = true }

        await withTaskGroup(of: (Int, Int64, Int).self) { group in
            for (i, cat) in categories.enumerated() {
                group.addTask {
                    let paths = cat.paths.map { URL(fileURLWithPath: $0) }
                    let size = paths.reduce(0) { $0 + DevToolsViewModel.measurePath($1) }
                    let count = paths.reduce(0) { $0 + DevToolsViewModel.countItems($1) }
                    return (i, size, count)
                }
            }
            for await (i, size, count) in group {
                categories[i].sizeBytes = size
                categories[i].fileCount = count
                categories[i].isScanning = false
                categories[i].isSelected = size > 0
            }
        }
    }

    func deleteSelected() async {
        guard !isDeleting else { return }
        isDeleting = true; defer { isDeleting = false }
        var freed: Int64 = 0
        for cat in selected {
            for pathStr in cat.paths {
                let url = URL(fileURLWithPath: pathStr)
                if FileManager.default.fileExists(atPath: pathStr) {
                    freed += DevToolsViewModel.measurePath(url)
                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
            }
        }
        freedBytes = freed
        showResult = true
        await scan()
    }

    func setSelectAll(_ value: Bool) {
        for i in categories.indices where categories[i].sizeBytes > 0 {
            categories[i].isSelected = value
        }
    }

    nonisolated static func measurePath(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        if let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true {
            return Int64(v.fileSize ?? 0)
        }
        var size: Int64 = 0
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true {
                size += Int64(v.fileSize ?? 0)
            }
        }
        return size
    }

    nonisolated static func countItems(_ url: URL) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        return (try? fm.contentsOfDirectory(atPath: url.path))?.count ?? 0
    }

    private static func buildCategories() -> [DevCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            DevCategory(id: "xcode-derived", name: "Xcode DerivedData",
                description: "Données de compilation Xcode",
                icon: "hammer.fill", accent: Color(red: 0.0, green: 0.48, blue: 1.0),
                paths: ["\(home)/Library/Developer/Xcode/DerivedData"]),
            DevCategory(id: "xcode-archives", name: "Archives Xcode",
                description: "Archives .xcarchive pour distribution",
                icon: "archivebox.fill", accent: .purple,
                paths: ["\(home)/Library/Developer/Xcode/Archives"]),
            DevCategory(id: "xcode-ios-sym", name: "Symboles iOS",
                description: "Symboles de débogage iPhone/iPad",
                icon: "iphone", accent: .blue,
                paths: ["\(home)/Library/Developer/Xcode/iOS DeviceSupport"]),
            DevCategory(id: "xcode-watch-sym", name: "Symboles watchOS",
                description: "Symboles de débogage Apple Watch",
                icon: "applewatch", accent: Color(red: 0.4, green: 0.7, blue: 0.4),
                paths: ["\(home)/Library/Developer/Xcode/watchOS DeviceSupport"]),
            DevCategory(id: "simulator-caches", name: "Caches simulateurs",
                description: "Données des simulateurs iOS/macOS",
                icon: "square.3.layers.3d.top.filled", accent: .teal,
                paths: ["\(home)/Library/Developer/CoreSimulator/Caches"]),
            DevCategory(id: "cocoapods", name: "CocoaPods",
                description: "Cache du gestionnaire CocoaPods",
                icon: "shippingbox.fill", accent: Color(red: 0.9, green: 0.3, blue: 0.3),
                paths: ["\(home)/.cocoapods/repos"]),
            DevCategory(id: "npm", name: "npm cache",
                description: "Cache des paquets Node.js",
                icon: "cube.fill", accent: Color(red: 0.8, green: 0.2, blue: 0.2),
                paths: ["\(home)/.npm/_cacache"]),
            DevCategory(id: "yarn", name: "Yarn cache",
                description: "Cache du gestionnaire Yarn",
                icon: "cube.fill", accent: Color(red: 0.1, green: 0.7, blue: 0.6),
                paths: ["\(home)/.yarn/cache"]),
            DevCategory(id: "pip", name: "pip cache",
                description: "Cache des paquets Python",
                icon: "snake", accent: Color(red: 0.2, green: 0.5, blue: 0.9),
                paths: ["\(home)/Library/Caches/pip"]),
            DevCategory(id: "gradle", name: "Gradle caches",
                description: "Cache de build Gradle (Android/Java)",
                icon: "gearshape.2.fill", accent: Color(red: 0.1, green: 0.7, blue: 0.3),
                paths: ["\(home)/.gradle/caches"]),
            DevCategory(id: "cargo", name: "Cargo registry",
                description: "Registre des crates Rust",
                icon: "shippingbox.fill", accent: Color(red: 0.8, green: 0.4, blue: 0.1),
                paths: ["\(home)/.cargo/registry"]),
        ]
    }
}

// MARK: - Section View

struct DevToolsSection: View {
    @ObservedObject var vm: DevToolsViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isScanning && !vm.hasScanned { loadingState }
            else { categoryList; Divider(); footer }
        }
        .onAppear { if !vm.hasScanned { Task { await vm.scan() } } }
        .confirmationDialog(
            "Déplacer \(vm.selected.count) catégorie\(vm.selected.count > 1 ? "s" : "") vers la Corbeille ?",
            isPresented: $vm.showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Déplacer vers la Corbeille", role: .destructive) { Task { await vm.deleteSelected() } }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("\(vm.totalSelectedBytes.formattedSize) seront supprimés. Ils seront recréés automatiquement.")
        }
        .alert("Nettoyage terminé", isPresented: $vm.showResult) { Button("OK") { } } message: {
            Text("\(vm.freedBytes.formattedSize) libérés. Les caches seront reconstruits à l'usage.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Outils développeur").font(.callout.weight(.semibold))
                Text("Caches Xcode, simulateurs, Node, Python, Rust…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isScanning { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.scan() } } label: {
                Label("Analyser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(vm.isScanning)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var loadingState: some View {
        VStack(spacing: 14) { Spacer(); ProgressView().scaleEffect(1.3)
            Text("Calcul des tailles…").foregroundStyle(.secondary); Spacer() }
    }

    private var categoryList: some View {
        ScrollView {
            let maxSize = vm.categories.map(\.sizeBytes).max() ?? 1
            LazyVStack(spacing: 5) {
                ForEach($vm.categories) { $cat in
                    DevCategoryRow(cat: $cat, maxSize: maxSize)
                }
            }
            .padding(12)
        }
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
            Text("\(vm.categories.filter { $0.sizeBytes > 0 }.count) catégorie\(vm.categories.filter { $0.sizeBytes > 0 }.count != 1 ? "s" : "") avec données")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            if vm.isDeleting {
                HStack(spacing: 6) { ProgressView().scaleEffect(0.75); Text("Nettoyage…").font(.callout).foregroundStyle(.secondary) }
            }
            if vm.totalSelectedBytes > 0 {
                Text("\(vm.totalSelectedBytes.formattedSize)").font(.callout.monospacedDigit().weight(.semibold))
            }
            Button { vm.showDeleteConfirm = true } label: {
                Label("Nettoyer", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
            .disabled(vm.selected.isEmpty || vm.isDeleting)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Category Row

struct DevCategoryRow: View {
    @Binding var cat: DevCategory
    let maxSize: Int64

    var body: some View {
        HStack(spacing: 10) {
            Button {
                guard cat.sizeBytes > 0 else { return }
                withAnimation(.spring(response: 0.3)) { cat.isSelected.toggle() }
            } label: {
                Image(systemName: cat.isSelected && cat.sizeBytes > 0 ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(cat.isSelected && cat.sizeBytes > 0 ? cat.accent : Color.secondary)
                    .frame(width: 24)
            }
            .buttonStyle(.plain)
            .disabled(cat.sizeBytes == 0 && !cat.isScanning)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(cat.accent.opacity(0.1)).frame(width: 36, height: 36)
                if cat.isScanning {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Image(systemName: cat.icon)
                        .font(.system(size: 14)).foregroundStyle(cat.accent)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cat.name).font(.body.weight(.medium))
                Text(cat.description).font(.caption).foregroundStyle(.secondary)
                if cat.sizeBytes > 0 && maxSize > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.1))
                            Capsule().fill(cat.accent.opacity(0.5))
                                .frame(width: max(4, geo.size.width * CGFloat(cat.sizeBytes) / CGFloat(maxSize)))
                        }
                    }
                    .frame(height: 4)
                }
            }

            Spacer()

            if cat.isScanning {
                Text("…").font(.caption).foregroundStyle(.tertiary)
            } else if cat.sizeBytes > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cat.sizeBytes.formattedSize)
                        .font(.callout.monospacedDigit().weight(.semibold))
                    if cat.fileCount > 0 {
                        Text("\(cat.fileCount) fichier\(cat.fileCount > 1 ? "s" : "")")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("Vide").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(cat.isSelected && cat.sizeBytes > 0 ? cat.accent.opacity(0.06) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(cat.isSelected && cat.sizeBytes > 0 ? cat.accent.opacity(0.25) : Color.clear, lineWidth: 1))
        .opacity(cat.sizeBytes == 0 && !cat.isScanning ? 0.45 : 1.0)
    }
}
