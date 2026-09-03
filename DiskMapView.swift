//
//  DiskMapView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct DiskMapItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let sizeBytes: Int64
    let colorIndex: Int
}

// MARK: - ViewModel

@MainActor
class DiskMapViewModel: ObservableObject {
    @Published var currentItems: [DiskMapItem] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var breadcrumb: [(name: String, url: URL)] = []

    var currentTitle: String { breadcrumb.last?.name ?? "Dossier personnel" }

    func scan() async {
        let url = breadcrumb.last?.url ?? FileManager.default.homeDirectoryForCurrentUser
        isScanning = true; hasScanned = true
        defer { isScanning = false }
        let result = await Task.detached(priority: .userInitiated) {
            DiskMapViewModel.scanDirectory(at: url)
        }.value
        withAnimation { currentItems = result }
    }

    func drillInto(_ item: DiskMapItem) async {
        breadcrumb.append((name: item.name, url: item.url))
        await scan()
    }

    func navigateTo(index: Int) async {
        guard index < breadcrumb.count else { return }
        breadcrumb = Array(breadcrumb.prefix(index + 1))
        await scan()
    }

    func navigateHome() async {
        breadcrumb = []
        await scan()
    }

    nonisolated static func scanDirectory(at url: URL) -> [DiskMapItem] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isHiddenKey]
        guard let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys) else { return [] }

        let visible = entries.filter { entry in
            guard !entry.lastPathComponent.hasPrefix(".") else { return false }
            let vals = try? entry.resourceValues(forKeys: Set(keys))
            return vals?.isHidden != true
        }

        var results: [DiskMapItem] = []
        for (i, entry) in visible.enumerated() {
            let size = dirSize(at: entry)
            if size > 0 {
                results.append(DiskMapItem(
                    name: entry.lastPathComponent, url: entry,
                    sizeBytes: size, colorIndex: i))
            }
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    nonisolated static func dirSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        let topKeys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        if let v = try? url.resourceValues(forKeys: topKeys), v.isRegularFile == true {
            return Int64(v.fileSize ?? 0)
        }
        var size: Int64 = 0
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(topKeys),
                                    options: [.skipsPackageDescendants]) else { return 0 }
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: topKeys), v.isRegularFile == true {
                size += Int64(v.fileSize ?? 0)
            }
        }
        return size
    }
}

// MARK: - Section View

struct DiskMapSection: View {
    @ObservedObject var vm: DiskMapViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isScanning || !vm.hasScanned { loadingState }
            else if vm.currentItems.isEmpty { emptyState }
            else { mapContent }
        }
        .onAppear { if !vm.hasScanned { Task { await vm.scan() } } }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Carte du disque").font(.callout.weight(.semibold))
                Text("Visualisation de l'espace par dossier — cliquez pour explorer")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !vm.breadcrumb.isEmpty {
                breadcrumbNav
            }
            if vm.isScanning { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.scan() } } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(vm.isScanning)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var breadcrumbNav: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button("~") { Task { await vm.navigateHome() } }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                ForEach(Array(vm.breadcrumb.enumerated()), id: \.offset) { i, crumb in
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Button(crumb.name) { Task { await vm.navigateTo(index: i) } }
                        .buttonStyle(.plain)
                        .font(.callout.weight(i == vm.breadcrumb.count - 1 ? .semibold : .regular))
                        .foregroundStyle(i == vm.breadcrumb.count - 1 ? .primary : .secondary)
                }
            }
        }
        .frame(maxWidth: 320)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().scaleEffect(1.3)
            Text("Calcul des tailles — \(vm.currentTitle)…").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text("Dossier vide").font(.title3.bold())
            Spacer()
        }
        .padding(32)
    }

    private var mapContent: some View {
        VStack(spacing: 0) {
            TreemapView(items: vm.currentItems) { item in
                Task { await vm.drillInto(item) }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            legend
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(vm.currentItems.prefix(10)) { item in
                    Button {
                        Task { await vm.drillInto(item) }
                    } label: {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(TreemapView.palette[item.colorIndex % TreemapView.palette.count])
                                .frame(width: 10, height: 10)
                            Text(item.name)
                                .font(.caption).lineLimit(1)
                                .foregroundStyle(.primary)
                            Text(item.sizeBytes.formattedSize)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if vm.currentItems.count > 10 {
                    Text("+ \(vm.currentItems.count - 10) autres")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }
}

// MARK: - Treemap View

struct TreemapView: View {
    let items: [DiskMapItem]
    let onTap: (DiskMapItem) -> Void

    static let palette: [Color] = [
        Color(red: 0.26, green: 0.52, blue: 0.96),
        Color(red: 0.20, green: 0.78, blue: 0.40),
        Color(red: 1.00, green: 0.60, blue: 0.00),
        Color(red: 0.68, green: 0.30, blue: 0.90),
        Color(red: 0.10, green: 0.75, blue: 0.75),
        Color(red: 0.95, green: 0.28, blue: 0.28),
        Color(red: 0.38, green: 0.40, blue: 0.95),
        Color(red: 0.95, green: 0.38, blue: 0.65),
        Color(red: 0.10, green: 0.85, blue: 0.65),
        Color(red: 0.00, green: 0.80, blue: 0.90),
        Color(red: 0.90, green: 0.70, blue: 0.10),
    ]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let total = items.reduce(0) { $0 + $1.sizeBytes }
            let rects = computeRects(size: size, total: total)
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(items.indices, rects)), id: \.0) { i, rect in
                    if rect.width > 2 && rect.height > 2 {
                        treemapCell(item: items[i], rect: rect,
                                    color: Self.palette[items[i].colorIndex % Self.palette.count])
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private func treemapCell(item: DiskMapItem, rect: CGRect, color: Color) -> some View {
        Button(action: { onTap(item) }) {
            ZStack {
                LinearGradient(
                    colors: [color.opacity(0.90), color.opacity(0.62)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if rect.width > 55 && rect.height > 35 {
                    VStack(spacing: 3) {
                        Text(item.name)
                            .font(rect.width > 110
                                  ? .callout.weight(.semibold)
                                  : .caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                        if rect.height > 58 && rect.width > 75 {
                            Text(item.sizeBytes.formattedSize)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.88))
                                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                        }
                    }
                    .padding(6)
                }
            }
            .frame(width: max(2, rect.width - 2), height: max(2, rect.height - 2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .help("\(item.name) — \(item.sizeBytes.formattedSize) — cliquer pour explorer")
    }

    private func computeRects(size: CGSize, total: Int64) -> [CGRect] {
        guard !items.isEmpty, total > 0 else { return [] }
        let horizontal = size.width >= size.height
        var result: [CGRect] = []
        var offset: CGFloat = 0

        for item in items {
            let fraction = CGFloat(item.sizeBytes) / CGFloat(total)
            let rect: CGRect
            if horizontal {
                let w = size.width * fraction
                rect = CGRect(x: offset, y: 0, width: w, height: size.height)
                offset += w
            } else {
                let h = size.height * fraction
                rect = CGRect(x: 0, y: offset, width: size.width, height: h)
                offset += h
            }
            result.append(rect)
        }
        return result
    }
}
