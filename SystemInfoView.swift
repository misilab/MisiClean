//
//  SystemInfoView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine
import Darwin
import IOKit

// MARK: - Model

struct SystemInfo {
    var modelName: String = "Mac"
    var modelID: String = ""
    var serialNumber: String = "—"
    var cpuBrand: String = ""
    var cpuCoreCount: Int = 0
    var totalRAMBytes: Int64 = 0
    var osName: String = ""
    var osBuild: String = ""
    var uptime: TimeInterval = 0
    var diskInfo: DiskInfo = DiskInfo(totalBytes: 0, availableBytes: 0)
    var batteryPercent: Int? = nil
    var isCharging: Bool? = nil
    var hasBattery: Bool = false
}

// MARK: - ViewModel

@MainActor
class SystemInfoViewModel: ObservableObject {
    @Published var info = SystemInfo()
    @Published var isLoading = true

    func load() async {
        isLoading = true
        let loaded = await Task.detached(priority: .userInitiated) {
            SystemInfoViewModel.loadAll()
        }.value
        info = loaded
        isLoading = false
    }

    nonisolated static func loadAll() -> SystemInfo {
        var info = SystemInfo()
        let pinfo = ProcessInfo.processInfo

        info.totalRAMBytes = Int64(pinfo.physicalMemory)
        info.cpuCoreCount  = pinfo.processorCount
        info.uptime        = pinfo.systemUptime

        let v = pinfo.operatingSystemVersion
        let macosNames: [(Int, String)] = [
            (16, "macOS 16"), (15, "Sequoia"), (14, "Sonoma"),
            (13, "Ventura"), (12, "Monterey"), (11, "Big Sur")
        ]
        let codeName = macosNames.first { $0.0 == v.majorVersion }?.1 ?? "macOS"
        info.osName = "\(codeName) \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"

        info.modelID  = sysctlStr("hw.model")
        info.cpuBrand = sysctlStr("machdep.cpu.brand_string")
        info.osBuild  = sysctlStr("kern.osversion")

        let expert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if expert != 0 {
            let cfVal = IORegistryEntryCreateCFProperty(expert, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0)
            info.serialNumber = (cfVal?.takeRetainedValue() as? String) ?? "—"
            IOObjectRelease(expert)
        }

        info.diskInfo = DiskInfo.load()
        let hw = systemProfilerHardware()
        info.modelName = hw.model.isEmpty ? info.modelID : hw.model
        // Apple Silicon: machdep.cpu.brand_string is empty — use chip_type from system_profiler
        if info.cpuBrand.isEmpty { info.cpuBrand = hw.chip }
        (info.batteryPercent, info.isCharging, info.hasBattery) = batteryStatus()

        return info
    }

    nonisolated private static func sysctlStr(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }

    nonisolated private static func systemProfilerHardware() -> (model: String, chip: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPHardwareDataType", "-json"]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return ("", "") }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list  = json["SPHardwareDataType"] as? [[String: Any]],
              let first = list.first else { return ("", "") }
        let model = first["machine_name"] as? String ?? ""
        let chip  = first["chip_type"] as? String ?? ""   // e.g. "Apple M2 Pro" on Apple Silicon
        return (model, chip)
    }

    nonisolated private static func batteryStatus() -> (percent: Int?, charging: Bool?, hasBattery: Bool) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["-g", "batt"]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return (nil, nil, false) }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard out.contains("InternalBattery") else { return (nil, nil, false) }
        for line in out.components(separatedBy: "\n") where line.contains("%") {
            if let range = line.range(of: #"\d+%"#, options: .regularExpression) {
                let pct = Int(line[range].dropLast())
                let charging = line.contains("charging") && !line.contains("discharging")
                return (pct, charging, true)
            }
        }
        return (nil, nil, true)
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
            else { infoContent }
        }
        .onAppear { Task { await vm.load() } }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mon Mac").font(.callout.weight(.semibold))
                Text("Informations matériel, logiciel et stockage")
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
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(1.3)
            Text("Lecture des informations système…").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var infoContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                hardwareCard
                softwareCard
                storageCard
                if vm.info.hasBattery { batteryCard }
            }
            .padding(16)
        }
    }

    // MARK: Cards

    private var hardwareCard: some View {
        infoCard(title: "Matériel", icon: "cpu") {
            if !vm.info.modelName.isEmpty {
                SysInfoRow(icon: "desktopcomputer", accent: .blue, label: "Modèle", value: vm.info.modelName)
            }
            if !vm.info.modelID.isEmpty && vm.info.modelID != vm.info.modelName {
                SysInfoRow(icon: "barcode", accent: .secondary, label: "Identifiant", value: vm.info.modelID)
            }
            SysInfoRow(icon: "number.circle.fill", accent: .secondary, label: "Numéro de série", value: vm.info.serialNumber)
            if !vm.info.cpuBrand.isEmpty {
                SysInfoRow(icon: "cpu.fill", accent: .purple, label: "Processeur", value: compactCPU(vm.info.cpuBrand))
            }
            SysInfoRow(icon: "bolt.fill", accent: Color(red: 0.9, green: 0.7, blue: 0.0),
                       label: "Cœurs", value: "\(vm.info.cpuCoreCount) cœur\(vm.info.cpuCoreCount > 1 ? "s" : "")")
            SysInfoRow(icon: "memorychip", accent: .green,
                       label: "Mémoire RAM", value: vm.info.totalRAMBytes.formattedSize)
        }
    }

    private var softwareCard: some View {
        infoCard(title: "Logiciel", icon: "gear") {
            if !vm.info.osName.isEmpty {
                SysInfoRow(icon: "laptopcomputer", accent: .primary, label: "Système", value: vm.info.osName)
            }
            if !vm.info.osBuild.isEmpty {
                SysInfoRow(icon: "hammer.fill", accent: .secondary, label: "Build", value: vm.info.osBuild)
            }
            SysInfoRow(icon: "clock.fill", accent: .teal,
                       label: "Temps de marche", value: formatUptime(vm.info.uptime))
        }
    }

    private var storageCard: some View {
        infoCard(title: "Stockage", icon: "internaldrive") {
            VStack(spacing: 10) {
                HStack {
                    Text("\(vm.info.diskInfo.usedBytes.formattedSize) utilisés")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("\(vm.info.diskInfo.availableBytes.formattedSize) libres / \(vm.info.diskInfo.totalBytes.formattedSize)")
                        .font(.callout).foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12))
                        Capsule()
                            .fill(diskBarColor)
                            .frame(width: max(4, geo.size.width * CGFloat(vm.info.diskInfo.usedFraction)))
                    }
                }
                .frame(height: 10)
                HStack {
                    Text("\(Int(vm.info.diskInfo.usedFraction * 100))% utilisé")
                        .font(.caption).foregroundStyle(diskBarColor)
                    Spacer()
                }
            }
        }
    }

    private var batteryCard: some View {
        infoCard(title: "Batterie", icon: "battery.100percent") {
            if let pct = vm.info.batteryPercent {
                VStack(spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: vm.info.isCharging == true ? "bolt.fill" : "battery.100percent")
                                .foregroundStyle(batteryColor(pct))
                            Text(vm.info.isCharging == true ? "En charge — \(pct)%" : "\(pct)%")
                                .font(.callout.weight(.medium))
                        }
                        Spacer()
                        Text(batteryLabel(pct, charging: vm.info.isCharging))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.12))
                            Capsule()
                                .fill(batteryColor(pct))
                                .frame(width: max(4, geo.size.width * CGFloat(pct) / 100.0))
                        }
                    }
                    .frame(height: 10)
                }
            } else {
                SysInfoRow(icon: "battery.100percent", accent: .green, label: "Batterie", value: "Non disponible")
            }
        }
    }

    // MARK: Helpers

    private func infoCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private var diskBarColor: Color {
        vm.info.diskInfo.usedFraction > 0.9 ? .red :
        vm.info.diskInfo.usedFraction > 0.75 ? .orange : .blue
    }

    private func batteryColor(_ pct: Int) -> Color {
        pct < 20 ? .red : pct < 50 ? .orange : .green
    }

    private func batteryLabel(_ pct: Int, charging: Bool?) -> String {
        if charging == true { return "En charge" }
        if pct < 20 { return "Batterie faible" }
        if pct < 50 { return "Batterie correcte" }
        return "Batterie bonne"
    }

    private func compactCPU(_ brand: String) -> String {
        brand
            .replacingOccurrences(of: "(R)", with: "")
            .replacingOccurrences(of: "(TM)", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private func formatUptime(_ ti: TimeInterval) -> String {
        let total = Int(ti)
        let days  = total / 86400
        let hours = (total % 86400) / 3600
        let mins  = (total % 3600) / 60
        if days > 0  { return "\(days)j \(hours)h \(mins)min" }
        if hours > 0 { return "\(hours)h \(mins)min" }
        return "\(mins)min"
    }
}

// MARK: - Info Row

struct SysInfoRow: View {
    let icon: String
    let accent: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(accent.opacity(0.1)).frame(width: 30, height: 30)
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(accent)
            }
            Text(label).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.weight(.medium))
                .multilineTextAlignment(.trailing).lineLimit(2)
        }
    }
}
