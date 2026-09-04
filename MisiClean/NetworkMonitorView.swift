//
//  NetworkMonitorView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct NetworkConnection: Identifiable {
    let id = UUID()
    let pid: Int
    let appName: String
    let addresses: [String]  // deduplicated
    var icon: NSImage?
}

// MARK: - ViewModel

@MainActor
final class NetworkMonitorViewModel: ObservableObject {
    @Published var connections: [NetworkConnection] = []
    @Published var isRefreshing = false
    @Published var autoRefresh = false
    @Published var lastRefreshed: Date? = nil

    private var refreshTask: Task<Void, Never>?

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        let output = await Task.detached(priority: .userInitiated) { () -> String in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            proc.arguments = ["-i", "TCP", "-F", "pcn", "+c", "0", "-sTCP:ESTABLISHED"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }.value

        // Parse -F pcn output:
        // p<PID>  — new process block
        // c<name> — command name
        // n<addr> — network address
        var groups: [Int: (name: String, addrs: [String])] = [:]
        var currentPID: Int? = nil

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard !line.isEmpty else { continue }
            let prefix = line.prefix(1)
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                if let pid = Int(value) {
                    currentPID = pid
                    if groups[pid] == nil {
                        groups[pid] = (name: "", addrs: [])
                    }
                }
            case "c":
                if let pid = currentPID {
                    // Only set the name if not already set (first block wins)
                    if groups[pid]?.name.isEmpty == true {
                        groups[pid]?.name = value
                    }
                }
            case "n":
                if let pid = currentPID {
                    groups[pid]?.addrs.append(value)
                }
            default:
                break
            }
        }

        var result: [NetworkConnection] = []
        for (pid, info) in groups {
            guard !info.name.isEmpty else { continue }
            let dedupedAddrs = Array(Set(info.addrs)).sorted()
            let runningApp = NSRunningApplication(processIdentifier: pid_t(pid))
            let icon = runningApp?.icon
            let conn = NetworkConnection(
                pid: pid,
                appName: info.name,
                addresses: dedupedAddrs,
                icon: icon
            )
            result.append(conn)
        }

        connections = result.sorted { $0.appName.localizedCompare($1.appName) == .orderedAscending }
        lastRefreshed = Date()
        isRefreshing = false
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}

// MARK: - Section View

struct NetworkMonitorSection: View {
    @ObservedObject var vm: NetworkMonitorViewModel

    private let accent = Color(red: 0, green: 0.55, blue: 0.9)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .onDisappear { vm.stopAutoRefresh() }
        .onChange(of: vm.autoRefresh) { newValue in
            if newValue {
                vm.startAutoRefresh()
            } else {
                vm.stopAutoRefresh()
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Moniteur réseau").font(.callout.weight(.semibold))
                subtitleText
            }
            Spacer()
            Toggle("Auto", isOn: $vm.autoRefresh)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            Text("Auto").font(.caption).foregroundStyle(.secondary)
            if vm.isRefreshing {
                ProgressView().scaleEffect(0.7)
            }
            Button {
                Task { await vm.refresh() }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(vm.isRefreshing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var subtitleText: some View {
        if let date = vm.lastRefreshed {
            let count = vm.connections.count
            Text("\(count) app\(count != 1 ? "s" : "") · actualisé à \(date.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Connexions TCP établies en temps réel")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if vm.lastRefreshed == nil && !vm.isRefreshing {
            idleHero
        } else if vm.connections.isEmpty && !vm.isRefreshing {
            emptyState
        } else {
            connectionsList
        }
    }

    // MARK: Idle Hero

    private var idleHero: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(accent.opacity(0.10))
                    .frame(width: 90, height: 90)
                Image(systemName: "network")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(accent)
            }
            VStack(spacing: 8) {
                Text("Moniteur réseau").font(.title3.bold())
                Text("Visualisez quelles apps ont des connexions TCP actives\net vers quels serveurs elles communiquent.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Button {
                Task { await vm.refresh() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                    Text("Scanner les connexions")
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 260)
                .padding(.vertical, 14)
                .background(accent, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: accent.opacity(0.45), radius: 14, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.green.opacity(0.6))
            VStack(spacing: 6) {
                Text("Aucune connexion active").font(.title3.bold())
                Text("Aucune application n'a de connexion TCP établie en ce moment.")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Connections list

    private var connectionsList: some View {
        List {
            ForEach(vm.connections) { conn in
                DisclosureGroup {
                    ForEach(conn.addresses, id: \.self) { addr in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.caption)
                                .foregroundStyle(accent.opacity(0.8))
                            Text(addr)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                } label: {
                    HStack(spacing: 10) {
                        // App icon or fallback
                        Group {
                            if let nsIcon = conn.icon {
                                Image(nsImage: nsIcon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "network")
                                    .font(.system(size: 18))
                                    .foregroundStyle(accent)
                                    .frame(width: 32, height: 32)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(conn.appName)
                                .font(.body.weight(.bold))
                                .lineLimit(1)
                            Text("PID \(conn.pid)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Badge: connection count
                        let count = conn.addresses.count
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accent, in: Capsule())
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
