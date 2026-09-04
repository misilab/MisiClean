import SwiftUI
import AppKit
import Combine

// MARK: - Models

struct StorageReport {
    struct PhysicalDisk {
        let deviceName: String
        let smartStatus: String
        let isInternal: Bool

        var healthColor: Color {
            switch smartStatus.lowercased() {
            case "verified": return Color(red: 0.1, green: 0.68, blue: 0.45)
            case let s where s.contains("fail"): return .red
            default: return .secondary
            }
        }
        var healthLabel: String {
            switch smartStatus.lowercased() {
            case "verified": return "Bon état"
            case let s where s.contains("fail"): return "Défaillant"
            default: return smartStatus
            }
        }
        var healthIcon: String {
            switch smartStatus.lowercased() {
            case "verified": return "checkmark.shield.fill"
            case let s where s.contains("fail"): return "exclamationmark.triangle.fill"
            default: return "questionmark.circle.fill"
            }
        }
    }

    struct Volume: Identifiable {
        let id: String
        let volumeName: String
        let bsdName: String
        let freeBytes: Int64
        let totalBytes: Int64
        let physicalDisk: PhysicalDisk?

        var usedFraction: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(totalBytes - freeBytes) / Double(totalBytes)
        }
    }

    struct NVMeDevice: Identifiable {
        let id: String
        let name: String
        let bsdName: String
        let smartStatus: String
        let sizeBytes: Int64
        let trimSupported: Bool
    }

    let volumes: [Volume]
    let nvmeDevices: [NVMeDevice]

    var primaryDisk: PhysicalDisk? {
        volumes.compactMap(\.physicalDisk).first
    }
}

// MARK: - ViewModel

@MainActor
final class DiskHealthViewModel: ObservableObject {
    @Published var report: StorageReport?
    @Published var isLoading: Bool = false
    @Published var hasLoaded: Bool = false

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let storageData = Task.detached(priority: .userInitiated) {
            runProcess("/usr/sbin/system_profiler", args: ["SPStorageDataType", "-json"])
        }.value
        async let nvmeData = Task.detached(priority: .userInitiated) {
            runProcess("/usr/sbin/system_profiler", args: ["SPNVMeDataType", "-json"])
        }.value
        let (storageJSON, nvmeJSON) = await (storageData, nvmeData)

        let volumes = parseVolumes(from: storageJSON)
        let nvmeDevices = parseNVMe(from: nvmeJSON)
        report = StorageReport(volumes: volumes, nvmeDevices: nvmeDevices)
        hasLoaded = true
    }
}

private func runProcess(_ executablePath: String, args: [String]) -> Data {
    let proc = Process()
    let pipe = Pipe()
    proc.executableURL = URL(fileURLWithPath: executablePath)
    proc.arguments = args
    proc.standardOutput = pipe
    proc.standardError = Pipe()
    do {
        try proc.run()
        proc.waitUntilExit()
    } catch { return Data() }
    return pipe.fileHandleForReading.readDataToEndOfFile()
}

private func parseVolumes(from data: Data) -> [StorageReport.Volume] {
    guard !data.isEmpty,
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let items = root["SPStorageDataType"] as? [[String: Any]]
    else { return [] }

    return items.enumerated().compactMap { idx, item in
        guard let name = item["_name"] as? String else { return nil }
        let bsd = item["bsd_name"] as? String ?? ""
        let free = item["free_space_in_bytes"] as? Int64
                ?? (item["free_space_in_bytes"] as? Int).map(Int64.init) ?? 0
        let total = item["size_in_bytes"] as? Int64
                 ?? (item["size_in_bytes"] as? Int).map(Int64.init) ?? 0

        var physDisk: StorageReport.PhysicalDisk?
        if let pd = item["physical_drive"] as? [String: Any] {
            let devName = pd["device_name"] as? String ?? ""
            let smart   = pd["smart_status"] as? String ?? "Unknown"
            let intern  = (pd["is_internal_disk"] as? String ?? "false") == "true"
            physDisk = StorageReport.PhysicalDisk(deviceName: devName, smartStatus: smart, isInternal: intern)
        }
        return StorageReport.Volume(id: bsd.isEmpty ? "\(idx)" : bsd,
                                    volumeName: name, bsdName: bsd,
                                    freeBytes: free, totalBytes: total,
                                    physicalDisk: physDisk)
    }
}

private func parseNVMe(from data: Data) -> [StorageReport.NVMeDevice] {
    guard !data.isEmpty,
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let items = root["SPNVMeDataType"] as? [[String: Any]]
    else { return [] }

    return items.enumerated().compactMap { idx, item in
        guard let name = item["_name"] as? String else { return nil }
        let bsd    = item["bsd_name"] as? String ?? ""
        let smart  = item["smart_status"] as? String ?? "Unknown"
        let size   = item["size_in_bytes"] as? Int64
                  ?? (item["size_in_bytes"] as? Int).map(Int64.init) ?? 0
        let trim   = (item["_sata_nvme_trim_support"] as? String ?? "").contains("supported")
        return StorageReport.NVMeDevice(id: bsd.isEmpty ? "\(idx)" : bsd,
                                        name: name, bsdName: bsd,
                                        smartStatus: smart, sizeBytes: size,
                                        trimSupported: trim)
    }
}

// MARK: - View

struct DiskHealthSection: View {
    @ObservedObject var vm: DiskHealthViewModel
    private let accent = Color(red: 0.1, green: 0.68, blue: 0.45)

    var body: some View {
        Group {
            if !vm.hasLoaded && !vm.isLoading {
                idleState
            } else if vm.isLoading {
                loadingState
            } else if let report = vm.report {
                dashboard(report: report)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Idle

    private var idleState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(accent)
            Text("Santé du disque")
                .font(.title2.bold())
            Text("Analysez l'état S.M.A.R.T. de vos disques, l'espace disponible\net la prise en charge du TRIM.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button {
                Task { await vm.load() }
            } label: {
                Label("Analyser", systemImage: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            Spacer()
        }
        .padding()
    }

    // MARK: Loading

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
            Text("Analyse en cours…")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Dashboard

    @ViewBuilder
    private func dashboard(report: StorageReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Santé du disque")
                        .font(.title3.bold())
                    Text(summaryText(report: report))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await vm.load() }
                } label: {
                    Label("Analyser", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    if let disk = report.primaryDisk {
                        healthCard(disk: disk)
                    }
                    volumesCard(volumes: report.volumes)
                    if !report.nvmeDevices.isEmpty {
                        nvmeCard(devices: report.nvmeDevices)
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: Health Card

    private func healthCard(disk: StorageReport.PhysicalDisk) -> some View {
        card {
            HStack(spacing: 18) {
                Image(systemName: disk.healthIcon)
                    .font(.system(size: 40))
                    .foregroundColor(disk.healthColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(disk.healthLabel)
                        .font(.title3.bold())
                        .foregroundColor(disk.healthColor)
                    Text(disk.deviceName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(disk.isInternal ? "Disque interne" : "Disque externe")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    // MARK: Volumes Card

    private func volumesCard(volumes: [StorageReport.Volume]) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Volumes", systemImage: "internaldrive")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                ForEach(volumes) { vol in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(vol.volumeName)
                                .font(.body.weight(.medium))
                            Spacer()
                            Text("\(vol.freeBytes.formattedSize) libres / \(vol.totalBytes.formattedSize)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(barColor(fraction: vol.usedFraction))
                                    .frame(width: geo.size.width * vol.usedFraction, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                    if vol.id != volumes.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: NVMe Card

    private func nvmeCard(devices: [StorageReport.NVMeDevice]) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Label("NVMe", systemImage: "memorychip")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                ForEach(devices) { dev in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dev.name)
                                .font(.body.weight(.medium))
                            Text(dev.sizeBytes.formattedSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            HStack(spacing: 4) {
                                Image(systemName: dev.smartStatus.lowercased() == "verified"
                                      ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundColor(dev.smartStatus.lowercased() == "verified" ? accent : .red)
                                    .font(.caption)
                                Text(dev.smartStatus)
                                    .font(.caption)
                            }
                            Text(dev.trimSupported ? "TRIM activé" : "TRIM inactif")
                                .font(.caption2)
                                .foregroundStyle(dev.trimSupported ? accent : .secondary)
                        }
                    }
                    if dev.id != devices.last?.id { Divider() }
                }
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func summaryText(report: StorageReport) -> String {
        if let disk = report.primaryDisk {
            return "\(report.volumes.count) volume(s) · \(disk.healthLabel)"
        }
        return "\(report.volumes.count) volume(s) détecté(s)"
    }

    private func barColor(fraction: Double) -> Color {
        fraction > 0.9 ? .red : fraction > 0.75 ? .orange : accent
    }
}

#Preview {
    DiskHealthSection(vm: DiskHealthViewModel())
        .frame(width: 560, height: 480)
}
