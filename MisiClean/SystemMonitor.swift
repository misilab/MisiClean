//
//  SystemMonitor.swift
//  MisiClean
//

import Foundation
import AppKit
import Combine
import Darwin

@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published var cpuPercent:   Int   = 0
    @Published var netUpBps:     Int64 = 0
    @Published var netDownBps:   Int64 = 0
    @Published var diskInfo:   DiskInfo = .load()
    @Published var ramUsedBytes: Int64 = 0
    @Published var ramTotalBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)

    var ramPercent: Int {
        ramTotalBytes > 0 ? max(0, min(100, Int(Double(ramUsedBytes) / Double(ramTotalBytes) * 100))) : 0
    }

    private var prevTicks:    [Int32]  = []
    private var prevBytesIn:  UInt64   = 0
    private var prevBytesOut: UInt64   = 0
    private var monitorTask:  Task<Void, Never>?

    private init() { start() }

    private func start() {
        // Baseline snapshots (no delta yet)
        Self.snapshotCPUTicks().map { prevTicks = $0 }
        let (i, o) = Self.snapshotNetwork()
        prevBytesIn = i; prevBytesOut = o

        monitorTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                let ticks          = Self.snapshotCPUTicks()
                let (bi, bo)       = Self.snapshotNetwork()
                let disk           = DiskInfo.load()
                let (ramU, ramT)   = Self.snapshotRAM()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.diskInfo      = disk
                    self.ramUsedBytes  = ramU
                    self.ramTotalBytes = ramT
                    self.updateCPU(newTicks: ticks)
                    self.updateNetwork(newIn: bi, newOut: bo)
                }
            }
        }
    }

    // MARK: CPU

    private func updateCPU(newTicks: [Int32]?) {
        guard let newTicks, !prevTicks.isEmpty, newTicks.count == prevTicks.count else {
            if let newTicks { prevTicks = newTicks }
            return
        }
        let numCPUs = newTicks.count / Int(CPU_STATE_MAX)
        var used: Double = 0; var total: Double = 0
        for i in 0..<numCPUs {
            let b = i * Int(CPU_STATE_MAX)
            let du = Double(newTicks[b + Int(CPU_STATE_USER)]   - prevTicks[b + Int(CPU_STATE_USER)])
            let ds = Double(newTicks[b + Int(CPU_STATE_SYSTEM)] - prevTicks[b + Int(CPU_STATE_SYSTEM)])
            let dn = Double(newTicks[b + Int(CPU_STATE_NICE)]   - prevTicks[b + Int(CPU_STATE_NICE)])
            let di = Double(newTicks[b + Int(CPU_STATE_IDLE)]   - prevTicks[b + Int(CPU_STATE_IDLE)])
            used  += du + ds + dn
            total += du + ds + dn + di
        }
        cpuPercent = total > 0 ? max(0, min(100, Int((used / total) * 100))) : 0
        prevTicks = newTicks
    }

    nonisolated private static func snapshotCPUTicks() -> [Int32]? {
        var numCPUs: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.size)) }
        var ticks: [Int32] = []
        for i in 0..<Int(numCPUs) * Int(CPU_STATE_MAX) { ticks.append(info[i]) }
        return ticks
    }

    // MARK: RAM

    nonisolated private static func snapshotRAM() -> (Int64, Int64) {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        let pageSize = Int64(vm_kernel_page_size)
        let used = (Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * pageSize
        return (min(used, total), total)
    }

    // MARK: Network

    private func updateNetwork(newIn: UInt64, newOut: UInt64) {
        if prevBytesIn > 0 {
            netDownBps = Int64(newIn  > prevBytesIn  ? (newIn  - prevBytesIn)  / 2 : 0)
            netUpBps   = Int64(newOut > prevBytesOut ? (newOut - prevBytesOut) / 2 : 0)
        }
        prevBytesIn = newIn; prevBytesOut = newOut
    }

    nonisolated private static func snapshotNetwork() -> (UInt64, UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        var totalIn: UInt64 = 0; var totalOut: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let flags = Int32(p.pointee.ifa_flags)
            let isLoopback = flags & IFF_LOOPBACK != 0
            if !isLoopback, let data = p.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                totalIn  += UInt64(data.pointee.ifi_ibytes)
                totalOut += UInt64(data.pointee.ifi_obytes)
            }
            ptr = p.pointee.ifa_next
        }
        return (totalIn, totalOut)
    }
}

// MARK: - Formatting helpers

extension Int64 {
    var bpsFormatted: String {
        let abs = self < 0 ? 0 : self
        if abs >= 1_000_000 { return String(format: "%.1f MB/s", Double(abs) / 1_000_000) }
        if abs >= 1_000     { return String(format: "%.0f KB/s", Double(abs) / 1_000) }
        return "\(abs) B/s"
    }
}
