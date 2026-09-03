//
//  MaintenanceView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Task model

struct MaintenanceTask: Identifiable {
    enum Kind: String {
        case flushDNS, rebuildLS, clearFontCache, reindexSpotlight, iconCache, periodicScripts
    }

    let id: Kind
    let name: String
    let description: String
    let icon: String
    let accent: Color
    let sudoCommand: String?
    var status: Status = .idle
    var lastRunDate: Date?

    enum Status { case idle, running, success, failed }

    var lastRunKey: String { "fr.misilab.MisiClean.maintenance.\(id.rawValue)" }

    var lastRunFormatted: String? {
        guard let d = lastRunDate else { return nil }
        if Calendar.current.isDateInToday(d) { return "Aujourd'hui" }
        if Calendar.current.isDateInYesterday(d) { return "Hier" }
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    var needsAttention: Bool {
        guard let d = lastRunDate else { return true }
        return (Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 99) > 30
    }
}

// MARK: - ViewModel

@MainActor
class MaintenanceViewModel: ObservableObject {
    @Published var tasks: [MaintenanceTask] = []
    @Published var isRunningAll = false

    init() {
        tasks = Self.defaultTasks().map { task in
            var t = task
            t.lastRunDate = UserDefaults.standard.object(forKey: t.lastRunKey) as? Date
            return t
        }
    }

    static func defaultTasks() -> [MaintenanceTask] { [
        MaintenanceTask(id: .flushDNS,
            name: "Vider le cache DNS",
            description: "Supprime les résolutions DNS mémorisées — résout les problèmes de connexion réseau",
            icon: "network", accent: .blue,
            sudoCommand: "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"),
        MaintenanceTask(id: .rebuildLS,
            name: "Base LaunchServices",
            description: "Reconstruit la base « Ouvrir avec… » et corrige les associations de fichiers cassées",
            icon: "arrow.triangle.2.circlepath", accent: .indigo,
            sudoCommand: nil),
        MaintenanceTask(id: .clearFontCache,
            name: "Cache de polices",
            description: "Vide le cache de polices utilisateur — corrige les problèmes d'affichage de texte",
            icon: "textformat", accent: .pink,
            sudoCommand: nil),
        MaintenanceTask(id: .reindexSpotlight,
            name: "Index Spotlight",
            description: "Réindexe le dossier personnel — améliore la pertinence des recherches Spotlight",
            icon: "magnifyingglass.circle.fill", accent: .purple,
            sudoCommand: nil),
        MaintenanceTask(id: .iconCache,
            name: "Cache d'icônes",
            description: "Supprime le cache d'icônes Finder et relance Dock — corrige les icônes manquantes",
            icon: "square.grid.2x2.fill", accent: .teal,
            sudoCommand: nil),
        MaintenanceTask(id: .periodicScripts,
            name: "Scripts périodiques",
            description: "Lance les scripts daily / weekly / monthly macOS (nécessite les droits admin)",
            icon: "terminal.fill", accent: .orange,
            sudoCommand: "sudo periodic daily weekly monthly"),
    ] }

    func run(taskID: MaintenanceTask.Kind) async {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }

        if let cmd = tasks[idx].sudoCommand {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
            withAnimation { tasks[idx].status = .success }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { tasks[idx].status = .idle }
            return
        }

        tasks[idx].status = .running
        let kind = taskID
        let success = await Task.detached(priority: .userInitiated) {
            MaintenanceViewModel.execute(kind)
        }.value

        let now = Date()
        UserDefaults.standard.set(now, forKey: tasks[idx].lastRunKey)
        withAnimation {
            tasks[idx].status = success ? .success : .failed
            tasks[idx].lastRunDate = now
        }
        try? await Task.sleep(for: .seconds(3))
        withAnimation { tasks[idx].status = .idle }
    }

    func runAll() async {
        guard !isRunningAll else { return }
        isRunningAll = true
        defer { isRunningAll = false }
        for task in tasks { await run(taskID: task.id) }
    }

    nonisolated static func execute(_ kind: MaintenanceTask.Kind) -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        switch kind {
        case .flushDNS:
            return run(executable: "/usr/bin/dscacheutil", args: ["-flushcache"])

        case .rebuildLS:
            let lsreg = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            return run(executable: lsreg, args: ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"])

        case .clearFontCache:
            var cleared = false
            for subpath in ["Library/Caches/com.apple.FontRegistry",
                            "Library/Caches/com.apple.ATS",
                            "Library/Caches/com.apple.font-registry-user"] {
                let url = home.appendingPathComponent(subpath)
                if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url); cleared = true }
            }
            return cleared

        case .reindexSpotlight:
            return run(executable: "/usr/bin/mdutil", args: ["-E", home.path])

        case .iconCache:
            let store = home.appendingPathComponent("Library/Caches/com.apple.iconservices.store")
            if fm.fileExists(atPath: store.path) { try? fm.removeItem(at: store) }
            _ = shell("killall Dock")
            _ = shell("killall Finder")
            return true

        case .periodicScripts:
            return false
        }
    }

    nonisolated static func shell(_ cmd: String) -> Bool {
        run(executable: "/bin/sh", args: ["-c", cmd])
    }

    nonisolated static func run(executable: String, args: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
}

// MARK: - Section View

struct MaintenanceSection: View {
    @ObservedObject var vm: MaintenanceViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(vm.tasks) { task in
                        MaintenanceRow(task: task) {
                            Task { await vm.run(taskID: task.id) }
                        }
                    }
                }
                .padding(12)
            }
            Divider()
            footer
        }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Maintenance système").font(.callout.weight(.semibold))
                Text("Tâches de maintenance macOS pour optimiser les performances et corriger les anomalies")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            let overdue = vm.tasks.filter { $0.needsAttention && $0.sudoCommand == nil }.count
            if overdue > 0 {
                Label("\(overdue) tâche\(overdue > 1 ? "s" : "") en attente",
                      systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Label("Maintenance à jour", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            Spacer()
            Button { Task { await vm.runAll() } } label: {
                Label(vm.isRunningAll ? "En cours…" : "Tout exécuter", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent).tint(.blue).controlSize(.large)
            .disabled(vm.isRunningAll)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Task Row

struct MaintenanceRow: View {
    let task: MaintenanceTask
    let onRun: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(iconBg).frame(width: 44, height: 44)
                statusIcon.transition(.scale.combined(with: .opacity))
            }
            .animation(.spring(response: 0.3), value: task.status)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.name).font(.body.weight(.medium))
                    if task.needsAttention && task.sudoCommand == nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if task.sudoCommand != nil {
                        Text("sudo")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(task.description).font(.caption).foregroundStyle(.secondary)
                if let lr = task.lastRunFormatted {
                    Text("Dernière exécution : \(lr)").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if task.status == .running {
                ProgressView().scaleEffect(0.75).frame(width: 88)
            } else {
                Button(action: onRun) {
                    Label(task.sudoCommand != nil ? "Copier" : "Exécuter",
                          systemImage: task.sudoCommand != nil ? "doc.on.clipboard" : "play.circle.fill")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .tint(task.sudoCommand != nil ? .secondary : task.accent)
            }
        }
        .padding(12)
        .background(rowBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(rowStroke, lineWidth: 1))
    }

    @ViewBuilder private var statusIcon: some View {
        switch task.status {
        case .running:
            ProgressView().scaleEffect(0.7)
        case .success:
            Image(systemName: task.sudoCommand != nil ? "doc.on.clipboard.fill" : "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(task.sudoCommand != nil ? task.accent : .green)
        case .failed:
            Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.red)
        case .idle:
            Image(systemName: task.icon).font(.system(size: 18)).foregroundStyle(task.accent)
        }
    }

    private var iconBg: Color {
        switch task.status {
        case .success: return .green.opacity(0.18)
        case .failed:  return .red.opacity(0.18)
        default:       return task.accent.opacity(0.12)
        }
    }
    private var rowBg: Color {
        switch task.status {
        case .success: return .green.opacity(0.06)
        case .failed:  return .red.opacity(0.06)
        default:       return .primary.opacity(0.03)
        }
    }
    private var rowStroke: Color {
        switch task.status {
        case .success: return .green.opacity(0.3)
        case .failed:  return .red.opacity(0.3)
        default:       return .clear
        }
    }
}
