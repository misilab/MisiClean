//
//  MenuBarView.swift
//  MisiClean
//

import SwiftUI
import AppKit

// MARK: - Menu Bar Label

struct MenuBarStatusLabel: View {
    @ObservedObject var monitor: SystemMonitor

    private var diskColor: Color {
        monitor.diskInfo.usedFraction > 0.9 ? .red
            : monitor.diskInfo.usedFraction > 0.75 ? .orange : .primary
    }
    private var cpuColor: Color {
        monitor.cpuPercent > 90 ? .red : monitor.cpuPercent > 70 ? .orange : .primary
    }
    private var ramColor: Color {
        monitor.ramPercent > 90 ? .red : monitor.ramPercent > 75 ? .orange : .primary
    }

    var body: some View {
        HStack(spacing: 5) {
            // CPU
            HStack(spacing: 2) {
                Image(systemName: "cpu").imageScale(.small)
                Text("\(monitor.cpuPercent)%")
                    .font(.caption.monospacedDigit().weight(.medium))
            }.foregroundStyle(cpuColor)

            // RAM
            HStack(spacing: 2) {
                Image(systemName: "memorychip").imageScale(.small)
                Text("\(monitor.ramPercent)%")
                    .font(.caption.monospacedDigit().weight(.medium))
            }.foregroundStyle(ramColor)

            // Network (toujours visible)
            VStack(alignment: .leading, spacing: -1) {
                HStack(spacing: 1) {
                    Image(systemName: "arrow.up").imageScale(.small)
                    Text(monitor.netUpBps.bpsFormatted)
                }
                HStack(spacing: 1) {
                    Image(systemName: "arrow.down").imageScale(.small)
                    Text(monitor.netDownBps.bpsFormatted)
                }
            }
            .font(.system(size: 8).monospacedDigit())
            .foregroundStyle(.primary)

            // Disque libre
            HStack(spacing: 2) {
                Image(systemName: monitor.diskInfo.usedFraction > 0.9 ? "internaldrive.fill" : "internaldrive")
                    .imageScale(.small)
                Text(monitor.diskInfo.availableBytes.formattedSize)
                    .font(.caption.monospacedDigit().weight(.medium))
            }.foregroundStyle(diskColor)
        }
    }
}

// MARK: - Quick Scan State

private enum QuickScanState {
    case idle, scanning, clean, threats(Int)

    var icon: String {
        switch self {
        case .idle:     return "shield"
        case .scanning: return "shield"
        case .clean:    return "checkmark.shield.fill"
        case .threats:  return "exclamationmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle:     return .secondary
        case .scanning: return .secondary
        case .clean:    return .green
        case .threats:  return .red
        }
    }

    var subtitle: String {
        switch self {
        case .idle:           return "Agents, processus, téléchargements…"
        case .scanning:       return "Analyse en cours…"
        case .clean:          return "Aucune menace détectée"
        case .threats(let n): return "\(n) élément\(n > 1 ? "s" : "") suspect\(n > 1 ? "s" : "") trouvé\(n > 1 ? "s" : "")"
        }
    }

    var isScanning: Bool { if case .scanning = self { return true }; return false }
}

// MARK: - Menu Bar Panel

struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow
    @State private var diskInfo = DiskInfo.load()
    @ObservedObject private var hm = HistoryManager.shared
    @ObservedObject private var updateManager = SelfUpdateManager.shared
    @State private var scanState: QuickScanState = .idle
    @State private var ramUsed: Int64 = 0
    @State private var ramTotal: Int64 = 0
    @State private var isHoveringClean = false
    @State private var isHoveringOpen  = false
    @State private var isHoveringQuit  = false
    @State private var isQuickCleaning = false
    @State private var quickCleanResult: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statsSection
            Divider()
            scanSection
            if !hm.events.isEmpty {
                Divider()
                historySnippet
            }
            if updateManager.availableUpdate != nil {
                Divider()
                updateSection
            }
            Divider()
            actions
        }
        .frame(width: 300)
        .onAppear {
            diskInfo = DiskInfo.load()
            loadRAM()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("MisiClean").font(.callout.weight(.semibold))
                Text("Nettoyeur Mac").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if updateManager.availableUpdate != nil {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                    .help("Mise à jour disponible")
            } else {
                Circle().fill(diskStatusColor).frame(width: 8, height: 8)
                    .help(diskStatusLabel)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Stats (Disk + RAM)

    private var statsSection: some View {
        VStack(spacing: 10) {
            statRow(
                icon: "internaldrive",
                label: "Disque",
                free: diskInfo.availableBytes.formattedSize,
                used: diskInfo.usedBytes.formattedSize,
                total: diskInfo.totalBytes.formattedSize,
                fraction: diskInfo.usedFraction,
                color: diskStatusColor
            )
            if ramTotal > 0 {
                let frac = min(Double(ramUsed) / Double(ramTotal), 1)
                let color: Color = frac > 0.9 ? .red : frac > 0.75 ? .orange : .blue
                statRow(
                    icon: "memorychip",
                    label: "Mémoire",
                    free: (ramTotal - ramUsed).formattedSize,
                    used: ramUsed.formattedSize,
                    total: ramTotal.formattedSize,
                    fraction: frac,
                    color: color
                )
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func statRow(icon: String, label: String, free: String, used: String, total: String, fraction: Double, color: Color) -> some View {
        VStack(spacing: 5) {
            HStack {
                Label(label, systemImage: icon).font(.caption)
                Spacer()
                Text("\(free) libres").font(.caption.monospacedDigit()).foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 5)
            HStack {
                Text("\(used) / \(total)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fraction * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Quick Antivirus Scan

    private var scanSection: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(scanState.color.opacity(0.12)).frame(width: 34, height: 34)
                if scanState.isScanning {
                    ProgressView().scaleEffect(0.65)
                } else {
                    Image(systemName: scanState.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(scanState.color)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Antivirus & Malwares").font(.caption.weight(.semibold))
                Text(scanState.subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(scanState.isScanning ? "…" : "Scanner") { runQuickScan() }
                .buttonStyle(.bordered).controlSize(.mini)
                .disabled(scanState.isScanning)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    // MARK: Last cleanup snippet

    private var historySnippet: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath").font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Dernier nettoyage").font(.caption).foregroundStyle(.secondary)
                if let last = hm.events.first {
                    Text("\(last.freedBytes.formattedSize) · \(last.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.primary)
                }
            }
            Spacer()
            Text("Total: \(hm.totalFreedBytes.formattedSize)").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: Update notification

    private var updateSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 22)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("v\(updateManager.availableUpdate?.version ?? "") disponible")
                    .font(.caption.weight(.semibold))
                Text("Nouvelle version prête").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Installer") { Task { await updateManager.downloadAndInstall() } }
                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.mini)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 2) {
            if let result = quickCleanResult {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20).padding(.top, 4)
            }
            menuButton(
                label: isQuickCleaning ? "Nettoyage en cours…" : "Nettoyage rapide",
                icon: isQuickCleaning ? "hourglass" : "sparkles",
                isHovering: isHoveringClean
            ) {
                guard !isQuickCleaning else { return }
                runQuickClean()
            }
            .onHover { isHoveringClean = $0 }
            .disabled(isQuickCleaning)

            menuButton(label: "Ouvrir MisiClean", icon: "macwindow", isHovering: isHoveringOpen) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .onHover { isHoveringOpen = $0 }

            menuButton(label: "Quitter", icon: "xmark.circle", isHovering: isHoveringQuit) {
                NSApp.terminate(nil)
            }
            .onHover { isHoveringQuit = $0 }
        }
        .padding(.vertical, 4)
    }

    private func menuButton(label: String, icon: String, isHovering: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(isHovering ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 6)
    }

    // MARK: Quick scan (étendu : agents, processus, téléchargements, chemins connus)

    private func runQuickScan() {
        scanState = .scanning
        Task.detached(priority: .userInitiated) {
            let count = MenuBarPanel.quickScan()
            await MainActor.run {
                withAnimation { self.scanState = count == 0 ? .clean : .threats(count) }
            }
        }
    }

    nonisolated private static func quickScan() -> Int {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let keywords = ["miner", "cryptominer", "adware", "spyware", "hijack", "payload",
                        "backdoor", "trojan", "rootkit", "keylogger", "ransom",
                        "malware", "virus", "worm", "exploit", "stealer", "rat", "botnet"]

        var found = 0

        // 1. LaunchAgents / Daemons
        let agentPaths = [
            home.appendingPathComponent("Library/LaunchAgents").path,
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
        ]
        for path in agentPaths {
            guard let items = try? fm.contentsOfDirectory(atPath: path) else { continue }
            for item in items {
                let lower = item.lowercased()
                if keywords.contains(where: { lower.contains($0) }) { found += 1; continue }
                let full = (path as NSString).appendingPathComponent(item)
                if let dict = NSDictionary(contentsOfFile: full) as? [String: Any] {
                    if keywords.contains(where: { "\(dict)".lowercased().contains($0) }) { found += 1 }
                }
            }
        }

        // 2. Processus en cours suspects
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "comm"]
        let psPipe = Pipe()
        ps.standardOutput = psPipe
        ps.standardError = Pipe()
        if (try? ps.run()) != nil {
            ps.waitUntilExit()
            let output = String(data: psPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for line in output.split(separator: "\n") {
                let lower = line.lowercased()
                if keywords.contains(where: { lower.contains($0) }) { found += 1 }
            }
        }

        // 3. Dossier Téléchargements (extensions exécutables suspects)
        let suspiciousExts = [".dmg.download", ".pkg.download", "backdoor", "crack", "keygen",
                              "patch", "hack", "trojan", "spy"]
        let downloads = home.appendingPathComponent("Downloads").path
        if let items = try? fm.contentsOfDirectory(atPath: downloads) {
            for item in items {
                let lower = item.lowercased()
                if suspiciousExts.contains(where: { lower.contains($0) })
                   || keywords.contains(where: { lower.contains($0) }) {
                    found += 1
                }
            }
        }

        // 4. Chemins malware connus
        let knownBadPaths = [
            "/Library/Application Support/com.vsearch",
            "/Library/Application Support/Genieo",
            "/Library/Application Support/VSearch",
            home.appendingPathComponent("Library/Application Support/Genieo").path,
            "/Library/InputManagers",
            "/System/Library/Extensions/NullCPU.kext",
        ]
        for path in knownBadPaths {
            if fm.fileExists(atPath: path) { found += 1 }
        }

        return found
    }

    // MARK: Quick clean

    private func runQuickClean() {
        isQuickCleaning = true
        quickCleanResult = nil
        Task.detached(priority: .utility) {
            let freed = MenuBarPanel.performQuickClean()
            await MainActor.run {
                self.isQuickCleaning = false
                self.quickCleanResult = freed > 1024 ? "\(freed.formattedSize) libérés" : "Déjà propre"
            }
        }
    }

    nonisolated private static func performQuickClean() -> Int64 {
        let fm = FileManager.default
        let tmpDirs = [
            NSTemporaryDirectory(),
            "/private/tmp/",
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs").path,
        ]
        var freed: Int64 = 0
        for dir in tmpDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items {
                let path = (dir as NSString).appendingPathComponent(item)
                if let attrs = try? fm.attributesOfItem(atPath: path) {
                    freed += (attrs[.size] as? Int64) ?? 0
                }
                try? fm.removeItem(atPath: path)
            }
        }
        return freed
    }

    // MARK: RAM

    private func loadRAM() {
        ramTotal = Int64(ProcessInfo.processInfo.physicalMemory)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/vm_stat")
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return }
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var pageSize: Int64 = 16384
        var active: Int64 = 0; var wire: Int64 = 0; var compressed: Int64 = 0
        for line in output.split(separator: "\n") {
            let s = String(line)
            if s.contains("page size of") {
                pageSize = s.components(separatedBy: " ").compactMap { Int64($0) }.last ?? 16384
            } else if s.contains("Pages active") {
                active = parse(s)
            } else if s.contains("Pages wired") {
                wire = parse(s)
            } else if s.contains("Pages occupied by compressor") {
                compressed = parse(s)
            }
        }
        ramUsed = min((active + wire + compressed) * pageSize, ramTotal)
    }

    private func parse(_ line: String) -> Int64 {
        Int64(line.components(separatedBy: ":").last?
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: "") ?? "") ?? 0
    }

    // MARK: Helpers

    private var diskStatusColor: Color {
        diskInfo.usedFraction > 0.9 ? .red : diskInfo.usedFraction > 0.75 ? .orange : .green
    }

    private var diskStatusLabel: String {
        diskInfo.usedFraction > 0.9 ? "Disque critique" : diskInfo.usedFraction > 0.75 ? "Espace limité" : "Espace suffisant"
    }
}
