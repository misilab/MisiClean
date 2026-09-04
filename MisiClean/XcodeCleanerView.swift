//
//  XcodeCleanerView.swift
//  MisiClean
//

import SwiftUI
import Combine

struct XcodeCleanCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let accent: Color
    let description: String
    let paths: [String]
    var sizeBytes: Int64 = 0
    var isSelected: Bool = false
    var isScanning: Bool = true
}

@MainActor
final class XcodeCleanerViewModel: ObservableObject {
    @Published var categories: [XcodeCleanCategory] = []
    @Published var isScanning = false
    @Published var isDeleting = false
    @Published var deletedBytes: Int64 = 0
    @Published var showResult = false

    var selectedBytes: Int64 { categories.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes } }
    var totalScannedBytes: Int64 { categories.reduce(0) { $0 + $1.sizeBytes } }

    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    init() { buildAndScan() }

    private func buildAndScan() {
        let h = home
        categories = [
            XcodeCleanCategory(
                name: "DerivedData",
                icon: "hammer.fill", accent: .orange,
                description: "Données de build — recréées automatiquement",
                paths: ["\(h)/Library/Developer/Xcode/DerivedData"]
            ),
            XcodeCleanCategory(
                name: "Archives",
                icon: "archivebox.fill", accent: .purple,
                description: "Archives d'applications exportées (.xcarchive)",
                paths: ["\(h)/Library/Developer/Xcode/Archives"]
            ),
            XcodeCleanCategory(
                name: "Caches simulateurs",
                icon: "iphone", accent: .blue,
                description: "Caches CoreSimulator (simulateurs conservés)",
                paths: ["\(h)/Library/Developer/CoreSimulator/Caches"]
            ),
            XcodeCleanCategory(
                name: "Support appareils iOS",
                icon: "cable.connector", accent: Color(red: 0.0, green: 0.55, blue: 0.88),
                description: "Symboles de débogage par version iOS",
                paths: ["\(h)/Library/Developer/Xcode/iOS DeviceSupport"]
            ),
            XcodeCleanCategory(
                name: "Support appareils watchOS",
                icon: "applewatch", accent: Color(red: 0.15, green: 0.75, blue: 0.35),
                description: "Symboles de débogage par version watchOS",
                paths: ["\(h)/Library/Developer/Xcode/watchOS DeviceSupport"]
            ),
            XcodeCleanCategory(
                name: "Cache Swift PM",
                icon: "shippingbox.fill", accent: Color(red: 0.95, green: 0.55, blue: 0.1),
                description: "Paquets Swift téléchargés (re-téléchargés au besoin)",
                paths: ["\(h)/Library/Caches/org.swift.swiftpm",
                        "\(h)/Library/org.swift.swiftpm"]
            ),
            XcodeCleanCategory(
                name: "Logs CoreSimulator",
                icon: "doc.text.fill", accent: .teal,
                description: "Journaux des simulateurs iOS/watchOS",
                paths: ["\(h)/Library/Logs/CoreSimulator"]
            ),
        ]
        scan()
    }

    func scan() {
        isScanning = true
        for i in categories.indices {
            categories[i].isScanning = true
            categories[i].sizeBytes = 0
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let cats = await MainActor.run { self.categories }

            for i in 0..<cats.count {
                var total: Int64 = 0
                for path in cats[i].paths {
                    total += Self.duSize(path)
                }
                let size = total
                await MainActor.run { [weak self] in
                    guard let self, self.categories.indices.contains(i) else { return }
                    self.categories[i].sizeBytes = size
                    self.categories[i].isScanning = false
                    self.categories[i].isSelected = size > 50_000_000
                }
            }
            await MainActor.run { [weak self] in self?.isScanning = false }
        }
    }

    func deleteSelected() {
        isDeleting = true
        deletedBytes = 0
        let selected = categories.filter(\.isSelected)

        Task.detached(priority: .userInitiated) { [weak self] in
            var freed: Int64 = 0
            for cat in selected {
                for path in cat.paths {
                    freed += Self.clearDirectory(path)
                }
            }
            await MainActor.run { [weak self] in
                self?.deletedBytes = freed
                self?.isDeleting = false
                self?.showResult = true
                self?.buildAndScan()
            }
        }
    }

    nonisolated private static func duSize(_ path: String) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return 0 }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard let kbStr = out.components(separatedBy: "\t").first,
              let kb = Int64(kbStr.trimmingCharacters(in: .whitespaces)) else { return 0 }
        return kb * 1024
    }

    nonisolated private static func clearDirectory(_ path: String) -> Int64 {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return 0 }
        var freed: Int64 = 0
        for item in items {
            let url = URL(fileURLWithPath: path).appendingPathComponent(item)
            if let size = try? url.resourceValues(forKeys: [.totalFileSizeKey]).totalFileSize {
                freed += Int64(size)
            }
            try? fm.removeItem(at: url)
        }
        return freed
    }
}

// MARK: - View

struct XcodeCleanerSection: View {
    @StateObject private var vm = XcodeCleanerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            categoryList
            Divider()
            footer
        }
        .alert("Nettoyage terminé", isPresented: $vm.showResult) {
            Button("OK") { }
        } message: {
            Text("\(vm.deletedBytes.formattedSize) libérés.")
        }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nettoyage Xcode").font(.callout.weight(.semibold))
                Text("DerivedData, archives, simulateurs et plus")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !vm.isScanning {
                Text("\(vm.totalScannedBytes.formattedSize) trouvés")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { vm.scan() } label: {
                Label(vm.isScanning ? "Analyse…" : "Ré-analyser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(vm.isScanning || vm.isDeleting)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var categoryList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach($vm.categories) { $cat in
                    XcodeCategoryRow(category: $cat)
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            if vm.isDeleting {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.75)
                    Text("Suppression en cours…").font(.callout).foregroundStyle(.secondary)
                }
            } else if vm.selectedBytes > 0 {
                Text("\(vm.selectedBytes.formattedSize) sélectionnés")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { vm.deleteSelected() } label: {
                Label("Nettoyer la sélection", systemImage: "trash")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.88, green: 0.15, blue: 0.15),
                                     Color(red: 0.7, green: 0.08, blue: 0.28)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .opacity(vm.selectedBytes == 0 || vm.isDeleting ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(vm.selectedBytes == 0 || vm.isDeleting)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

private struct XcodeCategoryRow: View {
    @Binding var category: XcodeCleanCategory

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(
                        colors: category.isSelected
                            ? [category.accent.opacity(0.32), category.accent.opacity(0.14)]
                            : [category.accent.opacity(0.16), category.accent.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                Group {
                    if category.isSelected {
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                    } else {
                        Image(systemName: category.icon).font(.system(size: 18))
                    }
                }
                .foregroundStyle(category.accent)
                .transition(.scale.combined(with: .opacity))
            }
            .animation(.spring(response: 0.3), value: category.isSelected)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.name).font(.body.weight(.medium))
                Text(category.description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if category.isScanning {
                ProgressView().scaleEffect(0.7).frame(width: 80)
            } else if category.sizeBytes > 0 {
                Text(category.sizeBytes.formattedSize)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(category.sizeBytes > 500_000_000 ? .red
                                   : category.sizeBytes > 100_000_000 ? .orange : .primary)
            } else {
                Text("Vide").font(.callout).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            category.isSelected ? category.accent.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(category.isSelected ? category.accent.opacity(0.2) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { category.isSelected.toggle() }
        .animation(.easeInOut(duration: 0.15), value: category.isSelected)
    }
}
