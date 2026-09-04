//
//  DormantAppsView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct DormantApp: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let bundleID: String
    let lastUsedDate: Date?
    let sizeBytes: Int64
    var isSelected: Bool = false
}

// MARK: - ViewModel

@MainActor
class DormantAppsViewModel: ObservableObject {
    @Published var apps: [DormantApp] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var ageFilter: AgeFilter = .oneYear

    enum AgeFilter: String, CaseIterable {
        case sixMonths = "6 mois"
        case oneYear   = "1 an"
        case twoYears  = "2 ans"

        var timeInterval: TimeInterval {
            switch self {
            case .sixMonths: return 6 * 30 * 24 * 3600
            case .oneYear:   return 365 * 24 * 3600
            case .twoYears:  return 2 * 365 * 24 * 3600
            }
        }
    }

    var filteredApps: [DormantApp] {
        let cutoff = Date().addingTimeInterval(-ageFilter.timeInterval)
        return apps
            .filter { app in
                guard let date = app.lastUsedDate else { return true }
                return date < cutoff
            }
            .sorted { a, b in
                switch (a.lastUsedDate, b.lastUsedDate) {
                case (nil, nil):       return a.name < b.name
                case (nil, _):         return true
                case (_, nil):         return false
                case let (d1?, d2?):   return d1 < d2
                }
            }
    }

    var totalSelectedBytes: Int64 {
        apps.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        apps = []
        defer { isScanning = false; hasScanned = true }

        let fm = FileManager.default
        let systemApps = URL(fileURLWithPath: "/Applications")
        let userApps   = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")

        var appURLs: [URL] = []
        for dir in [systemApps, userApps] {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
            ) else { continue }
            appURLs += entries.filter { $0.pathExtension == "app" }
        }

        var collected: [DormantApp] = []
        await withTaskGroup(of: DormantApp?.self) { group in
            for url in appURLs {
                group.addTask {
                    let bundleID = Self.bundleID(for: url)
                    if let bid = bundleID, bid.hasPrefix("com.apple.") { return nil }
                    let name        = url.deletingPathExtension().lastPathComponent
                    let lastUsed    = await Self.lastUsedDate(for: url)
                    let size        = Self.measureFolder(url)
                    return DormantApp(
                        url: url,
                        name: name,
                        bundleID: bundleID ?? "",
                        lastUsedDate: lastUsed,
                        sizeBytes: size
                    )
                }
            }
            for await result in group {
                if let app = result { collected.append(app) }
            }
        }

        apps = collected
    }

    func moveSelectedToTrash() {
        let fm = FileManager.default
        var remaining: [DormantApp] = []
        for app in apps {
            if app.isSelected {
                try? fm.trashItem(at: app.url, resultingItemURL: nil)
            } else {
                remaining.append(app)
            }
        }
        apps = remaining
    }

    // MARK: - Helpers (nonisolated)

    nonisolated static func bundleID(for url: URL) -> String? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    nonisolated static func lastUsedDate(for url: URL) async -> Date? {
        await Task.detached(priority: .utility) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
            task.arguments = ["-raw", "-name", "kMDItemLastUsedDate", url.path]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError  = Pipe()
            do {
                try task.run()
                task.waitUntilExit()
            } catch { return nil }
            let data   = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if output == "(null)" || output.isEmpty { return nil }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            return df.date(from: output)
        }.value
    }

    nonisolated static func measureFolder(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
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

// MARK: - View

struct DormantAppsSection: View {
    @ObservedObject var vm: DormantAppsViewModel

    private let accent = Color(red: 0.5, green: 0.28, blue: 0.92)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            if vm.hasScanned && !vm.filteredApps.isEmpty {
                footer
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apps dormantes")
                    .font(.headline)
                if vm.hasScanned {
                    Text("\(vm.filteredApps.count) app(s) — \(ByteCountFormatter.string(fromByteCount: vm.filteredApps.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("Période", selection: $vm.ageFilter) {
                ForEach(DormantAppsViewModel.AgeFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Button(action: { Task { await vm.scan() } }) {
                Label("Analyser", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(vm.isScanning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if vm.isScanning {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Analyse des applications…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else if !vm.hasScanned {
            emptyState
        } else if vm.filteredApps.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(accent)
                Text("Aucune app dormante trouvée")
                    .font(.title3.weight(.semibold))
                Text("Toutes vos apps ont été utilisées récemment.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else {
            List {
                ForEach(vm.filteredApps) { app in
                    appRow(app)
                }
            }
            .listStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(accent)
            Text("Apps dormantes")
                .font(.title2.weight(.semibold))
            Text("Trouvez les apps jamais ouvertes depuis \(vm.ageFilter.rawValue)")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: Row

    private func appRow(_ app: DormantApp) -> some View {
        HStack(spacing: 10) {
            if app.sizeBytes > 0 {
                let binding = Binding<Bool>(
                    get: { vm.apps.first(where: { $0.id == app.id })?.isSelected ?? false },
                    set: { val in
                        if let idx = vm.apps.firstIndex(where: { $0.id == app.id }) {
                            vm.apps[idx].isSelected = val
                        }
                    }
                )
                Toggle("", isOn: binding)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            } else {
                Spacer().frame(width: 18)
            }

            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.semibold))
                Text(app.bundleID.isEmpty ? "—" : app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(lastUsedLabel(app.lastUsedDate))
                    .font(.caption)
                    .foregroundStyle(app.lastUsedDate == nil ? .orange : .secondary)
                Text(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func lastUsedLabel(_ date: Date?) -> String {
        guard let date else { return "Jamais utilisée" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Sélectionné : \(ByteCountFormatter.string(fromByteCount: vm.totalSelectedBytes, countStyle: .file))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { vm.moveSelectedToTrash() }) {
                Label("Supprimer (mettre à la Corbeille)", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(vm.totalSelectedBytes == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
