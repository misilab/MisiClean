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
    let paths: [URL]
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
    @Published var showDeleteConfirm = false
    @Published var showResult = false
    @Published var freedBytes: Int64 = 0
    @Published var hasScanned = false

    var selectedCategories: [DevCategory] { categories.filter(\.isSelected) }
    var totalSelectedBytes: Int64 { selectedCategories.reduce(0) { $0 + $1.sizeBytes } }
    var maxCategorySize: Int64 { categories.map(\.sizeBytes).max() ?? 1 }

    init() { categories = Self.defaultCategories() }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true; hasScanned = true
        defer { isScanning = false }
        for i in categories.indices {
            categories[i].sizeBytes = 0
            categories[i].fileCount = 0
            categories[i].isSelected = false
            categories[i].isScanning = true
        }
        for i in categories.indices {
            let paths = categories[i].paths
            let (size, count) = await Task.detached(priority: .userInitiated) {
                (DevToolsViewModel.measurePaths(paths), DevToolsViewModel.countItems(paths))
            }.value
            withAnimation(.easeOut(duration: 0.3)) {
                categories[i].sizeBytes = size
                categories[i].fileCount = count
                categories[i].isScanning = false
                if size > 0 { categories[i].isSelected = true }
            }
        }
    }

    func setSelectAll(_ value: Bool) {
        withAnimation { for i in categories.indices where categories[i].sizeBytes > 0 { categories[i].isSelected = value } }
    }

    func deleteSelected() async {
        guard !isDeleting else { return }
        isDeleting = true; defer { isDeleting = false }
        var freed: Int64 = 0
        let toDelete = selectedCategories
        for cat in toDelete {
            freed += cat.sizeBytes
            for path in cat.paths where FileManager.default.fileExists(atPath: path.path) {
                try? FileManager.default.trashItem(at: path, resultingItemURL: nil)
            }
        }
        freedBytes = freed
        let deletedIDs = Set(toDelete.map(\.id))
        for i in categories.indices where deletedIDs.contains(categories[i].id) {
            categories[i].sizeBytes = 0; categories[i].fileCount = 0; categories[i].isSelected = false
        }
        showResult = true
    }

    func revealInFinder(_ cat: DevCategory) {
        if let first = cat.paths.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(first)
        }
    }

    nonisolated static func measurePaths(_ paths: [URL]) -> Int64 {
        paths.reduce(0) { $0 + dirSize(at: $1) }
    }

    nonisolated static func countItems(_ paths: [URL]) -> Int {
        let fm = FileManager.default
        return paths.reduce(0) { total, url in
            guard fm.fileExists(atPath: url.path) else { return total }
            let items = (try? fm.contentsOfDirectory(atPath: url.path))?.count ?? 0
            return total + max(items, 1)
        }
    }

    nonisolated private static func dirSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        let topKeys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        if let v = try? url.resourceValues(forKeys: topKeys), v.isRegularFile == true {
            return Int64(v.fileSize ?? 0)
        }
        var size: Int64 = 0
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(topKeys)) else { return 0 }
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: topKeys), v.isRegularFile == true {
                size += Int64(v.fileSize ?? 0)
            }
        }
        return size
    }

    static func defaultCategories() -> [DevCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let xcode = home.appendingPathComponent("Library/Developer/Xcode")
        let sim   = home.appendingPathComponent("Library/Developer/CoreSimulator")
        let caches = home.appendingPathComponent("Library/Caches")
        return [
            DevCategory(id: "xcode-derived",
                name: "Xcode DerivedData",
                description: "Index de build, symboles et fichiers compilés — régénérés automatiquement",
                icon: "hammer.fill", accent: .blue,
                paths: [xcode.appendingPathComponent("DerivedData")]),
            DevCategory(id: "xcode-archives",
                name: "Archives Xcode",
                description: "Archives .xcarchive des builds précédents — conservez uniquement les versions distribuées",
                icon: "archivebox.fill", accent: Color(red: 0.3, green: 0.55, blue: 0.9),
                paths: [xcode.appendingPathComponent("Archives")]),
            DevCategory(id: "xcode-device",
                name: "Symboles de débogage",
                description: "Symboles iOS/watchOS/tvOS/visionOS pour appareils physiques connectés",
                icon: "iphone.badge.play", accent: .indigo,
                paths: [
                    xcode.appendingPathComponent("iOS DeviceSupport"),
                    xcode.appendingPathComponent("watchOS DeviceSupport"),
                    xcode.appendingPathComponent("tvOS DeviceSupport"),
                    xcode.appendingPathComponent("visionOS DeviceSupport"),
                ]),
            DevCategory(id: "simulator-caches",
                name: "Caches simulateur",
                description: "Données mises en cache des simulateurs iOS et watchOS",
                icon: "ipad.and.iphone", accent: .teal,
                paths: [sim.appendingPathComponent("Caches")]),
            DevCategory(id: "cocoapods",
                name: "Cache CocoaPods",
                description: "Cache local des dépendances CocoaPods téléchargées",
                icon: "shippingbox.fill", accent: Color(red: 0.9, green: 0.3, blue: 0.25),
                paths: [caches.appendingPathComponent("CocoaPods")]),
            DevCategory(id: "npm",
                name: "Cache npm",
                description: "Cache des paquets Node.js téléchargés via npm",
                icon: "cube.fill", accent: Color(red: 0.75, green: 0.12, blue: 0.12),
                paths: [home.appendingPathComponent(".npm/_cacache")]),
            DevCategory(id: "yarn",
                name: "Cache Yarn",
                description: "Cache des paquets Node.js téléchargés via Yarn",
                icon: "cube.fill", accent: .cyan,
                paths: [caches.appendingPathComponent("Yarn"),
                        home.appendingPathComponent(".yarn/cache")]),
            DevCategory(id: "pip",
                name: "Cache pip",
                description: "Cache des paquets Python téléchargés via pip",
                icon: "chevron.left.forwardslash.chevron.right", accent: Color(red: 0.85, green: 0.65, blue: 0.1),
                paths: [caches.appendingPathComponent("pip")]),
            DevCategory(id: "gradle",
                name: "Cache Gradle",
                description: "Cache des dépendances Gradle pour les projets Android/Java",
                icon: "gearshape.2.fill", accent: Color(red: 0.1, green: 0.68, blue: 0.38),
                paths: [home.appendingPathComponent(".gradle/caches")]),
            DevCategory(id: "maven",
                name: "Cache Maven",
                description: "Dépôt local Maven (~/.m2) — dépendances Java téléchargées",
                icon: "gearshape.fill", accent: Color(red: 0.65, green: 0.2, blue: 0.1),
                paths: [home.appendingPathComponent(".m2/repository")]),
            DevCategory(id: "cargo",
                name: "Cache Cargo",
                description: "Cache du gestionnaire de paquets Rust (registry et sources)",
                icon: "gearshape.fill", accent: Color(red: 0.85, green: 0.35, blue: 0.1),
                paths: [home.appendingPathComponent(".cargo/registry/cache"),
                        home.appendingPathComponent(".cargo/registry/src")]),
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
            if !vm.hasScanned { welcomeState }
            else { categoryList; Divider(); footer }
        }
        .confirmationDialog(
            "Déplacer \(vm.selectedCategories.count) catégorie\(vm.selectedCategories.count > 1 ? "s" : "") vers la Corbeille ?",
            isPresented: $vm.showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Déplacer vers la Corbeille", role: .destructive) { Task { await vm.deleteSelected() } }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("\(vm.totalSelectedBytes.formattedSize) seront déplacés vers la Corbeille.")
        }
        .alert("Caches nettoyés", isPresented: $vm.showResult) { Button("OK") { } } message: {
            Text("\(vm.freedBytes.formattedSize) libérés.")
        }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Outils développeur").font(.callout.weight(.semibold))
                Text("Nettoyez les caches Xcode, npm, pip, Gradle et autres outils")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isScanning { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.scan() } } label: {
                Label(vm.isScanning ? "Analyse…" : "Analyser", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isScanning)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var welcomeState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hammer.circle.fill")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(Color.mint.opacity(0.5))
            VStack(spacing: 6) {
                Text("Libérez l'espace développeur").font(.title3.bold())
                Text("DerivedData, caches npm/pip/Gradle et symboles de débogage peuvent facilement occuper plusieurs Go.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(32)
    }

    private var categoryList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach($vm.categories) { $cat in
                    DevCategoryRow(category: $cat, maxSize: vm.maxCategorySize) {
                        vm.revealInFinder(cat)
                    }
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

            let total = vm.categories.filter { $0.sizeBytes > 0 }.reduce(0) { $0 + $1.sizeBytes }
            Text("\(total.formattedSize) détectés")
                .font(.caption).foregroundStyle(.tertiary)

            Spacer()

            if vm.totalSelectedBytes > 0 {
                Text("\(vm.totalSelectedBytes.formattedSize) sélectionnés")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { vm.showDeleteConfirm = true } label: {
                Label(vm.isDeleting ? "Nettoyage…" : "Nettoyer", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(.mint).controlSize(.large)
            .disabled(vm.selectedCategories.isEmpty || vm.isDeleting)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Category Row

struct DevCategoryRow: View {
    @Binding var category: DevCategory
    let maxSize: Int64
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(category.accent.opacity(category.isSelected ? 0.22 : 0.12))
                    .frame(width: 44, height: 44)
                Group {
                    if category.isScanning {
                        ProgressView().scaleEffect(0.65)
                    } else if category.isSelected && category.sizeBytes > 0 {
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                    } else {
                        Image(systemName: category.icon).font(.system(size: 18))
                    }
                }
                .foregroundStyle(category.accent)
                .transition(.scale.combined(with: .opacity))
            }
            .animation(.spring(response: 0.3), value: category.isSelected)
            .animation(.spring(response: 0.3), value: category.isScanning)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.name).font(.body.weight(.medium))
                    .foregroundStyle(category.sizeBytes > 0 || category.isScanning ? .primary : .secondary)
                Text(category.description).font(.caption).foregroundStyle(.secondary)
                if maxSize > 0 && category.sizeBytes > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.1))
                            Capsule()
                                .fill(category.accent.opacity(0.65))
                                .frame(width: max(3, geo.size.width * CGFloat(category.sizeBytes) / CGFloat(maxSize)))
                        }
                    }
                    .frame(height: 3).padding(.top, 2).transition(.opacity)
                }
            }

            Spacer()

            Group {
                if category.isScanning {
                    ProgressView().scaleEffect(0.7).frame(width: 80)
                } else if category.sizeBytes > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(category.sizeBytes.formattedSize)
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(category.sizeBytes > 1_000_000_000 ? .red : category.accent)
                        if category.fileCount > 0 {
                            Text("\(category.fileCount) élément\(category.fileCount > 1 ? "s" : "")")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(minWidth: 80, alignment: .trailing)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    HStack(spacing: 6) {
                        Text("—").foregroundStyle(.tertiary)
                        Button(action: onReveal) {
                            Image(systemName: "folder").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain).help("Ouvrir dans le Finder")
                        .opacity(FileManager.default.fileExists(atPath: category.paths.first?.path ?? "") ? 1 : 0)
                    }
                    .frame(minWidth: 80, alignment: .trailing)
                }
            }
            .animation(.easeOut(duration: 0.25), value: category.isScanning)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(category.isSelected ? category.accent.opacity(0.07) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(category.isSelected ? category.accent.opacity(0.35) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            guard category.sizeBytes > 0 else { return }
            withAnimation(.spring(response: 0.3)) { category.isSelected.toggle() }
        }
    }
}
