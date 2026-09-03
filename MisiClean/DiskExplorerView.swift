//
//  DiskExplorerView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct DiskItem: Identifiable {
    let id = UUID()
    let url: URL
    var sizeBytes: Int64
    let isDirectory: Bool
    var isLoadingSize: Bool = false

    var name: String { url.lastPathComponent }
    var ext: String { url.pathExtension.lowercased() }

    var accentColor: Color {
        if isDirectory { return .blue }
        switch ext {
        case "mp4", "mov", "avi", "mkv", "m4v":          return .purple
        case "dmg", "pkg", "zip", "rar", "gz", "7z":     return .orange
        case "jpg", "jpeg", "png", "gif", "heic", "raw": return .pink
        case "pdf":                                       return .red
        case "app":                                       return .indigo
        case "xcarchive", "xcodeproj", "xcworkspace":    return .teal
        default:                                          return .secondary
        }
    }
}

// MARK: - ViewModel

@MainActor
class DiskExplorerViewModel: ObservableObject {
    @Published var items: [DiskItem] = []
    @Published var currentURL: URL
    @Published var breadcrumbs: [URL] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var diskInfo: DiskInfo = .load()

    init() { currentURL = FileManager.default.homeDirectoryForCurrentUser }

    var totalShown: Int64 { items.filter { !$0.isLoadingSize }.reduce(0) { $0 + $1.sizeBytes } }
    var currentDirName: String { currentURL.lastPathComponent.isEmpty ? "/" : currentURL.lastPathComponent }

    func scan(at url: URL? = nil) async {
        let target = url ?? currentURL
        guard !isScanning else { return }
        isScanning = true
        hasScanned = true
        defer { isScanning = false }

        // Phase 1: list top-level items (instant)
        let listing = await Task.detached(priority: .userInitiated) {
            DiskExplorerViewModel.listTopLevel(target)
        }.value

        currentURL = target
        diskInfo = .load()
        withAnimation { items = listing }

        // Phase 2: measure directories in parallel
        await withTaskGroup(of: (UUID, Int64).self) { group in
            for item in items where item.isLoadingSize {
                group.addTask { [item] in
                    (item.id, DiskExplorerViewModel.measureDir(item.url))
                }
            }
            for await (itemID, size) in group {
                guard let idx = items.firstIndex(where: { $0.id == itemID }) else { continue }
                withAnimation(.easeOut(duration: 0.25)) {
                    items[idx].sizeBytes = size
                    items[idx].isLoadingSize = false
                }
            }
        }

        withAnimation(.easeOut(duration: 0.3)) {
            items.sort { $0.sizeBytes > $1.sizeBytes }
        }
    }

    func navigateInto(_ item: DiskItem) async {
        guard item.isDirectory else { return }
        breadcrumbs.append(currentURL)
        await scan(at: item.url)
    }

    func navigateBack() async {
        guard let prev = breadcrumbs.popLast() else { return }
        await scan(at: prev)
    }

    func navigateToBreadcrumb(index: Int) async {
        let target = breadcrumbs[index]
        breadcrumbs = Array(breadcrumbs.prefix(index))
        await scan(at: target)
    }

    func revealInFinder(_ item: DiskItem) {
        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
    }

    nonisolated static func listTopLevel(_ dir: URL) -> [DiskItem] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let contents = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [DiskItem] = []
        for url in contents {
            guard let v = try? url.resourceValues(forKeys: keys) else { continue }
            if v.isSymbolicLink == true { continue }
            let isDir = v.isDirectory ?? false
            if isDir {
                result.append(DiskItem(url: url, sizeBytes: 0, isDirectory: true, isLoadingSize: true))
            } else {
                result.append(DiskItem(url: url, sizeBytes: Int64(v.fileSize ?? 0), isDirectory: false))
            }
        }
        return result.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.sizeBytes > $1.sizeBytes
        }
    }

    nonisolated static func measureDir(_ url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var size: Int64 = 0
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            size += Int64(v.fileSize ?? 0)
        }
        return size
    }
}

// MARK: - Section View

struct DiskExplorerSection: View {
    @ObservedObject var vm: DiskExplorerViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if !vm.hasScanned { welcomeState }
            else {
                diskUsageBar.padding(16)
                Divider()
                itemList
            }
        }
    }

    // MARK: Toolbar with breadcrumb

    private var toolbar: some View {
        HStack(spacing: 8) {
            if !vm.breadcrumbs.isEmpty {
                Button { Task { await vm.navigateBack() } } label: {
                    Image(systemName: "chevron.left").font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(vm.breadcrumbs.indices, id: \.self) { i in
                        Button(vm.breadcrumbs[i].lastPathComponent.isEmpty ? "Racine" : vm.breadcrumbs[i].lastPathComponent) {
                            Task { await vm.navigateToBreadcrumb(index: i) }
                        }
                        .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(vm.currentDirName).font(.callout.weight(.semibold))
                }
                .padding(.vertical, 2)
            }

            Spacer()

            if vm.isScanning { ProgressView().scaleEffect(0.7) }

            Button { Task { await vm.scan() } } label: {
                Label(vm.isScanning ? "Analyse…" : "Analyser", systemImage: "folder.badge.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isScanning)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: Disk usage bar

    private var diskUsageBar: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Disque de démarrage", systemImage: "internaldrive.fill").font(.callout.weight(.medium))
                Spacer()
                Text("\(vm.diskInfo.availableBytes.formattedSize) disponibles")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.1))
                    Capsule()
                        .fill(diskGradient)
                        .frame(width: max(6, geo.size.width * CGFloat(vm.diskInfo.usedFraction)))
                }
            }
            .frame(height: 8)
            HStack {
                Text("\(vm.diskInfo.usedBytes.formattedSize) utilisés sur \(vm.diskInfo.totalBytes.formattedSize)")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(vm.diskInfo.usedFraction * 100))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(diskColor)
            }
        }
    }

    private var diskColor: Color {
        vm.diskInfo.usedFraction > 0.9 ? .red : vm.diskInfo.usedFraction > 0.75 ? .orange : .blue
    }

    private var diskGradient: LinearGradient {
        LinearGradient(colors: [diskColor, diskColor.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Item list

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                let maxSize = vm.items.first(where: { !$0.isLoadingSize })?.sizeBytes ?? 1
                ForEach(vm.items) { item in
                    DiskItemRow(item: item, maxSize: maxSize) {
                        Task { await vm.navigateInto(item) }
                    } onReveal: {
                        vm.revealInFinder(item)
                    }
                }
            }
            .padding(12)
        }
    }

    private var welcomeState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "folder.badge.magnifyingglass")
                .font(.system(size: 60, weight: .thin)).foregroundStyle(.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text("Explorateur d'espace disque").font(.title3.bold())
                Text("Voyez exactement où votre espace est utilisé,\ndossier par dossier, avec percée en profondeur.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Disk Item Row

struct DiskItemRow: View {
    let item: DiskItem
    let maxSize: Int64
    let onNavigate: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.callout.weight(item.isDirectory ? .medium : .regular))
                    .lineLimit(1)

                if !item.isLoadingSize && maxSize > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.08))
                            Capsule()
                                .fill(item.accentColor.opacity(0.55))
                                .frame(width: max(2, geo.size.width * CGFloat(item.sizeBytes) / CGFloat(maxSize)))
                        }
                    }
                    .frame(height: 3)
                }
            }

            Spacer()

            if item.isLoadingSize {
                ProgressView().scaleEffect(0.6).frame(width: 80)
            } else {
                Text(item.sizeBytes.formattedSize)
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(sizeColor)
                    .frame(minWidth: 80, alignment: .trailing)
            }

            HStack(spacing: 4) {
                Button(action: onReveal) {
                    Image(systemName: "folder").font(.callout).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Afficher dans le Finder")

                if item.isDirectory {
                    Button(action: onNavigate) {
                        Image(systemName: "chevron.right").font(.callout).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).help("Explorer ce dossier")
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if item.isDirectory { onNavigate() } }
    }

    private var sizeColor: Color {
        if item.sizeBytes > 1_000_000_000 { return .red }
        if item.sizeBytes > 500_000_000   { return .orange }
        return .primary
    }
}
