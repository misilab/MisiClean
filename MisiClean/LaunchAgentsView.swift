//
//  LaunchAgentsView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct LaunchItem: Identifiable {
    enum Source: String, CaseIterable, Identifiable {
        case userAgent    = "Utilisateur"
        case systemAgent  = "Système"
        case systemDaemon = "Démons"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .userAgent:    return "person.circle.fill"
            case .systemAgent:  return "gearshape.fill"
            case .systemDaemon: return "server.rack"
            }
        }
        var accent: Color {
            switch self {
            case .userAgent:    return .blue
            case .systemAgent:  return .orange
            case .systemDaemon: return .red
            }
        }
        var canToggle: Bool { self == .userAgent }
    }

    let id = UUID()
    let label: String
    let plistURL: URL
    let source: Source
    let executable: String
    let runsAtLoad: Bool
    var isLoaded: Bool
}

// MARK: - ViewModel

@MainActor
class LaunchAgentsViewModel: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var filterSource: LaunchItem.Source? = nil
    @Published var togglingID: UUID? = nil

    var filtered: [LaunchItem] {
        guard let f = filterSource else { return items }
        return items.filter { $0.source == f }
    }

    var availableSources: [LaunchItem.Source] {
        let seen = Set(items.map(\.source.rawValue))
        return LaunchItem.Source.allCases.filter { seen.contains($0.rawValue) }
    }

    func load() async {
        isLoading = true; hasLoaded = true
        defer { isLoading = false }
        let result = await Task.detached(priority: .userInitiated) {
            LaunchAgentsViewModel.scanAll()
        }.value
        withAnimation { items = result }
    }

    func toggle(_ item: LaunchItem) async {
        guard item.source.canToggle else { return }
        togglingID = item.id
        defer { togglingID = nil }
        let args = item.isLoaded
            ? ["unload", "-w", item.plistURL.path]
            : ["load",   "-w", item.plistURL.path]
        let success = await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            proc.arguments = args
            proc.standardOutput = Pipe(); proc.standardError = Pipe()
            guard (try? proc.run()) != nil else { return false }
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        }.value
        if success, let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isLoaded = !item.isLoaded
        }
    }

    func reveal(_ item: LaunchItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.plistURL])
    }

    nonisolated static func scanAll() -> [LaunchItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let loaded = loadedLabels()

        let sources: [(URL, LaunchItem.Source)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"),       .systemAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"),      .systemDaemon),
        ]

        var items: [LaunchItem] = []
        var seen = Set<String>()

        for (dir, source) in sources {
            guard let plists = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for plist in plists where plist.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: plist),
                      let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { continue }

                let label = dict["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
                guard !seen.contains(label) else { continue }
                seen.insert(label)

                let executable: String
                if let prog = dict["Program"] as? String {
                    executable = (prog as NSString).lastPathComponent
                } else if let args = dict["ProgramArguments"] as? [String], let first = args.first {
                    executable = (first as NSString).lastPathComponent
                } else {
                    executable = "—"
                }

                let runsAtLoad = dict["RunAtLoad"] as? Bool ?? false
                items.append(LaunchItem(
                    label: label, plistURL: plist, source: source,
                    executable: executable, runsAtLoad: runsAtLoad,
                    isLoaded: loaded.contains(label)))
            }
        }
        return items.sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
    }

    nonisolated private static func loadedLabels() -> Set<String> {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["list"]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var labels = Set<String>()
        for line in out.components(separatedBy: "\n").dropFirst() {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 3 {
                let lbl = parts[2].trimmingCharacters(in: .whitespaces)
                if !lbl.isEmpty { labels.insert(lbl) }
            }
        }
        return labels
    }
}

// MARK: - Section View

struct LaunchAgentsSection: View {
    @ObservedObject var vm: LaunchAgentsViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isLoading || !vm.hasLoaded { loadingState }
            else if vm.items.isEmpty { emptyState }
            else { itemList; Divider(); statusBar }
        }
        .onAppear { Task { await vm.load() } }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Agents de lancement").font(.callout.weight(.semibold))
                Text("Processus lancés silencieusement par macOS — \(vm.items.count) détecté\(vm.items.count != 1 ? "s" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !vm.availableSources.isEmpty {
                Picker("", selection: $vm.filterSource) {
                    Text("Tous").tag(LaunchItem.Source?.none)
                    ForEach(vm.availableSources) { s in
                        Text(s.rawValue).tag(Optional(s))
                    }
                }
                .pickerStyle(.segmented).frame(maxWidth: 240)
            }
            if vm.isLoading { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.load() } } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(vm.isLoading)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().scaleEffect(1.3)
            Text("Lecture des agents de lancement…").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(Color.green.opacity(0.5))
            Text("Aucun agent détecté").font(.title3.bold())
            Spacer()
        }
        .padding(32)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(vm.filtered) { item in
                    LaunchItemRow(
                        item: item,
                        isToggling: vm.togglingID == item.id,
                        onToggle: { Task { await vm.toggle(item) } },
                        onReveal: { vm.reveal(item) }
                    )
                }
            }
            .padding(12)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            let loaded = vm.filtered.filter(\.isLoaded).count
            ForEach(LaunchItem.Source.allCases) { source in
                let count = vm.items.filter { $0.source == source }.count
                if count > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(source.accent).frame(width: 6, height: 6)
                        Text("\(count) \(source.rawValue.lowercased())")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text("\(loaded) actif\(loaded != 1 ? "s" : "") / \(vm.filtered.count)")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

// MARK: - Item Row

struct LaunchItemRow: View {
    let item: LaunchItem
    let isToggling: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.source.accent.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: item.source.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(item.source.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.executable).font(.caption).foregroundStyle(.secondary)
                    if item.runsAtLoad {
                        Text("Au démarrage")
                            .font(.caption2).foregroundStyle(item.source.accent)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(item.source.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if item.source.canToggle {
                    if isToggling {
                        ProgressView().scaleEffect(0.7).frame(width: 72)
                    } else {
                        Button(item.isLoaded ? "Désactiver" : "Activer") { onToggle() }
                            .buttonStyle(.bordered)
                            .tint(item.isLoaded ? .red : .green)
                            .controlSize(.small)
                    }
                } else {
                    Text(item.isLoaded ? "Actif" : "Inactif")
                        .font(.caption2)
                        .foregroundStyle(item.isLoaded ? Color.green : Color.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                }

                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Afficher dans le Finder")
            }
        }
        .padding(10)
        .background(Color.primary.opacity(item.isLoaded ? 0.03 : 0.015), in: RoundedRectangle(cornerRadius: 8))
        .opacity(item.isLoaded ? 1.0 : 0.65)
    }
}
