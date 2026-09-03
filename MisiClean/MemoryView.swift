//
//  MemoryView.swift
//  MisiClean
//

import SwiftUI
import Darwin
import AppKit
import Combine

// MARK: - ViewModel

@MainActor
class MemoryViewModel: ObservableObject {
    @Published var memInfo: MemoryInfo = .zero
    @Published var processes: [MemoryProcess] = []
    @Published var isRefreshing = false
    @Published var swapUsed: Int64 = 0

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let (mem, procs, swap) = await Task.detached(priority: .userInitiated) {
            (MemoryViewModel.loadMemoryInfo(),
             MemoryViewModel.loadTopProcesses(),
             MemoryViewModel.loadSwapUsed())
        }.value

        withAnimation(.easeOut(duration: 0.4)) {
            memInfo = mem; processes = procs; swapUsed = swap
        }
    }

    nonisolated static func loadMemoryInfo() -> MemoryInfo {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                _ = host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let page = Int64(vm_page_size)
        return MemoryInfo(
            totalBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            freeBytes: Int64(stats.free_count) * page,
            activeBytes: Int64(stats.active_count) * page,
            inactiveBytes: Int64(stats.inactive_count) * page,
            wiredBytes: Int64(stats.wire_count) * page,
            compressedBytes: Int64(stats.compressor_page_count) * page
        )
    }

    nonisolated static func loadSwapUsed() -> Int64 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sysctl")
        proc.arguments = ["vm.swapusage"]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return 0 }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for part in out.components(separatedBy: "used = ").dropFirst() {
            let tokens = part.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            if let v = tokens.first.flatMap(Double.init) {
                let u = tokens.count > 1 ? tokens[1] : "B"
                if u.hasPrefix("G") { return Int64(v * 1_000_000_000) }
                if u.hasPrefix("M") { return Int64(v * 1_000_000) }
                if u.hasPrefix("K") { return Int64(v * 1_000) }
                return Int64(v)
            }
        }
        return 0
    }

    nonisolated static func loadTopProcesses() -> [MemoryProcess] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-axo", "pid,rss,comm"]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var result: [MemoryProcess] = []
        for line in out.components(separatedBy: "\n").dropFirst() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            var parts = t.components(separatedBy: .whitespaces)
            guard parts.count >= 3, let pid = Int(parts[0]), let rssKB = Int64(parts[1]) else { continue }
            parts.removeFirst(2)
            let name = URL(fileURLWithPath: parts.joined(separator: " ")).lastPathComponent
            result.append(MemoryProcess(pid: pid, name: name, rssBytes: rssKB * 1024))
        }
        return Array(result.sorted { $0.rssBytes > $1.rssBytes }.prefix(15))
    }
}

// MARK: - Section

struct MemorySection: View {
    @ObservedObject var vm: MemoryViewModel
    @State private var copiedCommand = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    ramCard
                    if vm.swapUsed > 0 { swapRow }
                    processesCard
                    purgeInfoCard
                }
                .padding(16)
            }
        }
        .onAppear { Task { await vm.refresh() } }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mémoire RAM")
                    .font(.callout.weight(.semibold))
                Text("\(vm.memInfo.totalBytes.formattedSize) installés · macOS optimise la mémoire automatiquement")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isRefreshing { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.refresh() } } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(vm.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: RAM card — barre corrigée via GeometryReader

    private var ramCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Utilisation RAM").font(.headline)
                Spacer()
                Text("\(vm.memInfo.usedBytes.formattedSize) / \(vm.memInfo.totalBytes.formattedSize)")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let total = Double(vm.memInfo.totalBytes)
                HStack(spacing: 2) {
                    if total > 0 {
                        ramSegment(color: .red,                       fraction: Double(vm.memInfo.wiredBytes)      / total, totalW: w)
                        ramSegment(color: .blue,                      fraction: Double(vm.memInfo.activeBytes)     / total, totalW: w)
                        ramSegment(color: .yellow,                    fraction: Double(vm.memInfo.compressedBytes) / total, totalW: w)
                        ramSegment(color: .secondary.opacity(0.35),   fraction: Double(vm.memInfo.inactiveBytes)   / total, totalW: w)
                        ramSegment(color: .green.opacity(0.6),        fraction: Double(vm.memInfo.freeBytes)       / total, totalW: w)
                    }
                }
                .frame(width: w, height: 20)
                .clipShape(Capsule())
            }
            .frame(height: 20)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                legendItem(color: .red,                     label: "Câblée",       value: vm.memInfo.wiredBytes)
                legendItem(color: .blue,                    label: "Active",      value: vm.memInfo.activeBytes)
                legendItem(color: .yellow,                  label: "Compressée",  value: vm.memInfo.compressedBytes)
                legendItem(color: .secondary.opacity(0.5),  label: "Inactive",    value: vm.memInfo.inactiveBytes)
                legendItem(color: .green,                   label: "Libre",        value: vm.memInfo.freeBytes)
                legendItem(color: .purple,                  label: "Disponible",   value: vm.memInfo.availableBytes)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private func ramSegment(color: Color, fraction: Double, totalW: CGFloat) -> some View {
        Rectangle().fill(color).frame(width: max(0, CGFloat(fraction) * totalW))
    }

    private func legendItem(color: Color, label: String, value: Int64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value.formattedSize).font(.caption.monospacedDigit().weight(.medium))
            }
        }
    }

    // MARK: Swap

    private var swapRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: "externaldrive.fill").foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Mémoire d'échange (Swap)").font(.callout.weight(.medium))
                Text("Le disque est utilisé comme extension de la RAM. Redémarrer peut aider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(vm.swapUsed.formattedSize)
                .font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(.orange)
        }
        .padding(12)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2), lineWidth: 1))
    }

    // MARK: Processes

    private var processesCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Processus les plus gourmands").font(.headline)
                Spacer()
                Text("RAM résidente").font(.caption).foregroundStyle(.tertiary)
            }
            if vm.processes.isEmpty {
                Text("Chargement…").foregroundStyle(.secondary).padding()
            } else {
                let maxRSS = vm.processes.first?.rssBytes ?? 1
                ForEach(vm.processes) { proc in ProcessRow(process: proc, maxRSS: maxRSS) }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Purge info (honnête)

    private var purgeInfoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill").foregroundStyle(.secondary).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("À propos du nettoyage RAM")
                    .font(.callout.weight(.medium))
                Text("macOS libère automatiquement la mémoire inactive lorsqu'une app en a besoin. Forcer la libération n'améliore pas les performances durablement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("sudo purge", forType: .string)
                copiedCommand = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    copiedCommand = false
                }
            } label: {
                Label(copiedCommand ? "Copié !" : "sudo purge", systemImage: copiedCommand ? "checkmark" : "doc.on.clipboard")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Copie « sudo purge » dans le presse-papiers — coller dans Terminal pour forcer la libération (nécessite le mot de passe admin)")
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Process Row

struct ProcessRow: View {
    let process: MemoryProcess
    let maxRSS: Int64

    var body: some View {
        HStack(spacing: 10) {
            Text(process.name)
                .font(.callout).lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.1))
                    Capsule().fill(barColor)
                        .frame(width: max(3, geo.size.width * CGFloat(process.rssBytes) / CGFloat(maxRSS)))
                }
            }
            .frame(height: 6)
            Text(process.rssBytes.formattedSize)
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private var barColor: Color {
        let f = Double(process.rssBytes) / Double(maxRSS)
        return f > 0.7 ? .red : f > 0.4 ? .orange : .blue
    }
}
