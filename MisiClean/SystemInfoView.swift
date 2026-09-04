//
//  SystemInfoView.swift
//  MisiClean
//

import SwiftUI
import IOKit
import Darwin
import Combine

// MARK: - Model

struct SystemInfo {
    let modelName: String
    let modelID: String
    let serialNumber: String
    let cpuBrand: String
    let cpuCoreCount: Int
    let totalRAMBytes: Int64
    let osName: String
    let osBuild: String
    let uptime: TimeInterval
    let diskInfo: DiskInfo?
    let batteryPercent: Double?
    let isCharging: Bool
    let hasBattery: Bool
}

// MARK: - ViewModel

@MainActor
class SystemInfoViewModel: ObservableObject {
    @Published var info: SystemInfo?
    @Published var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let result = await Task.detached(priority: .userInitiated) {
            SystemInfoViewModel.readSystemInfo()
        }.value
        info = result
    }

    nonisolated static func readSystemInfo() -> SystemInfo {
        let proc = ProcessInfo.processInfo

        let osVersion = proc.operatingSystemVersion
        let osName    = macOSName(major: osVersion.majorVersion)
        let osBuild   = sysctlString("kern.osversion")

        let cpuBrand = sysctlString("machdep.cpu.brand_string")
            .trimmingCharacters(in: .whitespaces)
        var cpuCount: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.physicalcpu", &cpuCount, &size, nil, 0)

        let modelID   = sysctlString("hw.model")
        let modelName = readModelName(fallback: modelID)
        let serial    = readSerial()
        let ramBytes  = Int64(proc.physicalMemory)
        let uptime    = proc.systemUptime
        let disk      = DiskInfo.load()
        let (batPct, charging, hasBat) = readBattery()

        return SystemInfo(
            modelName: modelName, modelID: modelID, serialNumber: serial,
            cpuBrand: cpuBrand, cpuCoreCount: Int(cpuCount),
            totalRAMBytes: ramBytes,
            osName: "\(osName) \(osVersion.majorVersion).\(osVersion.minorVersion)",
            osBuild: osBuild,
            uptime: uptime, diskInfo: disk,
            batteryPercent: batPct, isCharging: charging, hasBattery: hasBat)
    }

    nonisolated private static func sysctlString(_ key: String) -> String {
        var size = 0
        sysctlbyname(key, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(key, &buf, &size, nil, 0)
        return String(cString: buf)
    }

    nonisolated private static func readModelName(fallback: String) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPHardwareDataType", "-json"]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return fallback }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hw = (json["SPHardwareDataType"] as? [[String: Any]])?.first,
              let name = hw["machine_name"] as? String else { return fallback }
        if let chip = hw["chip_type"] as? String { return "\(name) (\(chip))" }
        return name
    }

    nonisolated private static func readSerial() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return "—" }
        defer { IOObjectRelease(service) }
        let key = "IOPlatformSerialNumber" as CFString
        guard let val = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0) else { return "—" }
        return (val.takeRetainedValue() as? String) ?? "—"
    }

    nonisolated private static func readBattery() -> (Double?, Bool, Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, false, false) }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return (nil, false, false) }
        let max     = dict["MaxCapacity"]     as? Int ?? 0
        let current = dict["CurrentCapacity"] as? Int ?? 0
        let charging = dict["IsCharging"]     as? Bool ?? false
        guard max > 0 else { return (nil, false, false) }
        return (Double(current) / Double(max) * 100.0, charging, true)
    }

    nonisolated private static func macOSName(major: Int) -> String {
        switch major {
        case 16: return "macOS 16"
        case 15: return "Sequoia"
        case 14: return "Sonoma"
        case 13: return "Ventura"
        case 12: return "Monterey"
        case 11: return "Big Sur"
        default: return "macOS"
        }
    }

    var uptimeString: String {
        guard let s = info?.uptime else { return "—" }
        let days    = Int(s) / 86400
        let hours   = (Int(s) % 86400) / 3600
        let minutes = (Int(s) % 3600) / 60
        if days > 0  { return "\(days)j \(hours)h \(minutes)min" }
        if hours > 0 { return "\(hours)h \(minutes)min" }
        return "\(minutes) min"
    }
}

// MARK: - Section View

struct SystemInfoSection: View {
    @ObservedObject var vm: SystemInfoViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isLoading { loadingState }
            else if let info = vm.info { infoContent(info) }
            else { loadingState }
        }
        .onAppear { Task { await vm.load() } }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Informations système").font(.callout.weight(.semibold))
                Text(vm.info.map { "\($0.modelName) · \($0.osName)" } ?? "Chargement…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
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
        VStack(spacing: 14) { Spacer(); ProgressView().scaleEffect(1.3)
            Text("Lecture du système…").foregroundStyle(.secondary); Spacer() }
    }

    @ViewBuilder
    private func infoContent(_ info: SystemInfo) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                hardwareCard(info)
                softwareCard(info)
                storageCard(info)
                if info.hasBattery { batteryCard(info) }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func hardwareCard(_ info: SystemInfo) -> some View {
        sectionCard(title: "Matériel", icon: "desktopcomputer", accent: .blue) {
            SysInfoRow(icon: "macpro.gen3.fill", accent: .blue, label: "Modèle", value: info.modelName)
            Divider().padding(.vertical, 4)
            SysInfoRow(icon: "barcode", accent: .blue, label: "N° de série", value: info.serialNumber)
            Divider().padding(.vertical, 4)
            SysInfoRow(icon: "cpu.fill", accent: .orange, label: "Processeur", value: info.cpuBrand)
            Divider().padding(.vertical, 4)
            SysInfoRow(icon: "cpu", accent: .orange, label: "Cœurs physiques", value: "\(info.cpuCoreCount)")
            Divider().padding(.vertical, 4)
            SysInfoRow(icon: "memorychip.fill", accent: .purple, label: "Mémoire RAM", value: info.totalRAMBytes.formattedSize)
        }
    }

    @ViewBuilder
    private func softwareCard(_ info: SystemInfo) -> some View {
        sectionCard(title: "Logiciel", icon: "apple.logo", accent: .secondary) {
            SysInfoRow(icon: "apple.logo", accent: .secondary, label: "Système", value: info.osName)
            Divider().padding(.vertical, 4)
            SysInfoRow(icon: "chevron.left.forwardslash.chevron.right", accent: .secondary, label: "Build", value: info.osBuild)
            Divider().padding(.vertical, 4)
            SysInfoRow(icon: "clock.fill", accent: .green, label: "Uptime", value: vm.uptimeString)
        }
    }

    @ViewBuilder
    private func storageCard(_ info: SystemInfo) -> some View {
        if let disk = info.diskInfo {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.teal.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "internaldrive.fill").font(.system(size: 13)).foregroundStyle(.teal)
                    }
                    Text("Stockage").font(.callout.weight(.semibold))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.1))
                        Capsule()
                            .fill(storageColor(disk.usedFraction))
                            .frame(width: max(4, geo.size.width * disk.usedFraction))
                    }
                }
                .frame(height: 8)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Utilisé").font(.caption).foregroundStyle(.secondary)
                        Text(disk.usedBytes.formattedSize).font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(storageColor(disk.usedFraction))
                    }
                    Spacer()
                    VStack(alignment: .center, spacing: 2) {
                        Text("Libre").font(.caption).foregroundStyle(.secondary)
                        Text(disk.availableBytes.formattedSize).font(.callout.monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total").font(.caption).foregroundStyle(.secondary)
                        Text(disk.totalBytes.formattedSize).font(.callout.monospacedDigit())
                    }
                }
            }
            .padding(16)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func storageColor(_ fraction: Double) -> Color {
        if fraction > 0.9 { return .red }
        if fraction > 0.75 { return .orange }
        return .teal
    }

    @ViewBuilder
    private func batteryCard(_ info: SystemInfo) -> some View {
        if let pct = info.batteryPercent {
            sectionCard(title: "Batterie", icon: "battery.75", accent: .green) {
                SysInfoRow(icon: info.isCharging ? "bolt.fill" : "battery.75",
                           accent: .green,
                           label: "Charge",
                           value: String(format: "%.0f%%", pct) + (info.isCharging ? " — En charge" : ""))
            }
        }
    }

    private func sectionCard<Content: View>(title: String, icon: String, accent: Color,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon).font(.system(size: 13)).foregroundStyle(accent)
                }
                Text(title).font(.callout.weight(.semibold))
            }
            VStack(spacing: 0) { content() }
        }
        .padding(16)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Info Row

struct SysInfoRow: View {
    let icon: String
    let accent: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(accent.opacity(0.12))
                    .frame(width: 24, height: 24)
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(accent)
            }
            Text(label).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospacedDigit())
                .lineLimit(1).truncationMode(.tail)
        }
    }
}
