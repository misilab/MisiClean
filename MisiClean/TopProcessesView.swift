//
//  TopProcessesView.swift
//  MisiClean
//

import SwiftUI
import Combine
import Darwin

struct ProcessItem: Identifiable {
    let pid: Int
    let name: String
    let cpu: Double
    let ramBytes: Int64
    var id: Int { pid }
}

enum ProcessSortOrder { case cpu, ram }

@MainActor
final class TopProcessesViewModel: ObservableObject {
    @Published var items: [ProcessItem] = []
    @Published var sort: ProcessSortOrder = .cpu
    @Published var isRefreshing = false
    @Published var confirmKill: ProcessItem? = nil

    private var pollingTask: Task<Void, Never>?

    init() { startPolling() }
    deinit { pollingTask?.cancel() }

    private func startPolling() {
        pollingTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let procs = Self.fetchProcesses()
                await MainActor.run { [weak self] in self?.items = procs }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func refresh() {
        isRefreshing = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let procs = Self.fetchProcesses()
            await MainActor.run { [weak self] in
                self?.items = procs
                self?.isRefreshing = false
            }
        }
    }

    func kill(_ item: ProcessItem) {
        Darwin.kill(pid_t(item.pid), SIGTERM)
        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            let procs = Self.fetchProcesses()
            await MainActor.run { [weak self] in self?.items = procs }
        }
    }

    var sorted: [ProcessItem] {
        let list = sort == .cpu
            ? items.sorted { $0.cpu > $1.cpu }
            : items.sorted { $0.ramBytes > $1.ramBytes }
        return Array(list.prefix(60))
    }

    nonisolated private static func fetchProcesses() -> [ProcessItem] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid,pcpu,rss,comm"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        p.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return output.split(separator: "\n").dropFirst()
            .compactMap { line -> ProcessItem? in
                let parts = line.trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                guard parts.count >= 4,
                      let pid = Int(parts[0]),
                      let cpu = Double(parts[1]),
                      let rss = Int64(parts[2]) else { return nil }
                let comm = parts[3...].joined(separator: " ")
                let name = URL(fileURLWithPath: comm).lastPathComponent
                return ProcessItem(pid: pid,
                                   name: name.isEmpty ? comm : name,
                                   cpu: cpu,
                                   ramBytes: rss * 1024)
            }
    }
}

// MARK: - Section View

struct TopProcessesSection: View {
    @StateObject private var vm = TopProcessesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableHeader
            Divider()
            processList
        }
        .confirmationDialog(
            "Forcer à quitter \(vm.confirmKill?.name ?? "") ?",
            isPresented: Binding(
                get: { vm.confirmKill != nil },
                set: { if !$0 { vm.confirmKill = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = vm.confirmKill {
                Button("Forcer à quitter", role: .destructive) {
                    vm.kill(item)
                    vm.confirmKill = nil
                }
                Button("Annuler", role: .cancel) { vm.confirmKill = nil }
            }
        } message: {
            Text("Le processus sera arrêté immédiatement.")
        }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Processus actifs").font(.callout.weight(.semibold))
                Text("\(vm.items.count) processus · mise à jour toutes les 3 s")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Trier par", selection: $vm.sort) {
                Text("CPU").tag(ProcessSortOrder.cpu)
                Text("RAM").tag(ProcessSortOrder.ram)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)

            Button { vm.refresh() } label: {
                Label(vm.isRefreshing ? "…" : "Actualiser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(vm.isRefreshing)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("Processus")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("PID")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text("CPU")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text("RAM")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Spacer().frame(width: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.04))
    }

    private var processList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.sorted) { item in
                    TopProcessRow(item: item, onKill: { vm.confirmKill = item })
                    Divider().padding(.leading, 16)
                }
            }
        }
    }
}

private struct TopProcessRow: View {
    let item: ProcessItem
    let onKill: () -> Void
    @State private var isHovering = false

    private var cpuColor: Color {
        item.cpu > 50 ? .red : item.cpu > 20 ? .orange : .green
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.08))
                        Capsule()
                            .fill(cpuColor.opacity(0.6))
                            .frame(width: max(2, geo.size.width * CGFloat(min(item.cpu, 100)) / 100))
                    }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(item.pid)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            Text(String(format: "%.1f%%", item.cpu))
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(cpuColor)
                .frame(width: 80, alignment: .trailing)

            Text(item.ramBytes.formattedSize)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            Button(action: onKill) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary.opacity(isHovering ? 0.7 : 0.2))
            }
            .buttonStyle(.plain)
            .frame(width: 44, alignment: .center)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(isHovering ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { isHovering = $0 }
    }
}
