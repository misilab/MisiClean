//
//  BatteryView.swift
//  MisiClean
//

import SwiftUI
import IOKit
import Combine

// MARK: - Model

struct BatteryInfo {
    let cycleCount: Int
    let designCapacity: Int
    let maxCapacity: Int
    let currentCapacity: Int
    let isCharging: Bool
    let isFullyCharged: Bool
    let temperature: Double
    let timeRemaining: Int
    let amperage: Int
    let voltage: Int

    var healthPercent: Double {
        guard designCapacity > 0 else { return 1.0 }
        return min(1.0, Double(maxCapacity) / Double(designCapacity))
    }
    var chargePercent: Double {
        guard maxCapacity > 0 else { return 0 }
        return min(1.0, Double(currentCapacity) / Double(maxCapacity))
    }
    var healthLabel: String {
        let p = healthPercent
        if p > 0.85 { return "Excellent" }
        if p > 0.70 { return "Bon" }
        if p > 0.50 { return "Usé" }
        return "À remplacer"
    }
    var healthColor: Color {
        let p = healthPercent
        if p > 0.85 { return .green }
        if p > 0.70 { return .orange }
        return .red
    }
    var cycleLabel: String {
        if cycleCount < 200 { return "Neuf" }
        if cycleCount < 500 { return "Bon" }
        if cycleCount < 800 { return "Usé" }
        return "Fin de vie"
    }
    var cycleColor: Color {
        if cycleCount < 200 { return .green }
        if cycleCount < 500 { return .blue }
        if cycleCount < 800 { return .orange }
        return .red
    }
    var timeRemainingString: String {
        if isFullyCharged { return "Chargée" }
        if isCharging { return "En charge…" }
        guard timeRemaining > 0 && timeRemaining < 1440 else { return "Calcul…" }
        let h = timeRemaining / 60, m = timeRemaining % 60
        if h == 0 { return "\(m) min" }
        return "\(h) h \(String(format: "%02d", m)) min"
    }
    var powerWatts: Double {
        Double(abs(amperage)) * Double(voltage) / 1_000_000.0
    }
}

// MARK: - ViewModel

@MainActor
class BatteryViewModel: ObservableObject {
    @Published var info: BatteryInfo?
    @Published var hasBattery = false
    @Published var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let result = await Task.detached(priority: .userInitiated) {
            BatteryViewModel.readBattery()
        }.value
        hasBattery = result != nil
        info = result
    }

    nonisolated static func readBattery() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props,
                                                kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

        return BatteryInfo(
            cycleCount:      dict["CycleCount"]      as? Int  ?? 0,
            designCapacity:  dict["DesignCapacity"]  as? Int  ?? 0,
            maxCapacity:     dict["MaxCapacity"]     as? Int  ?? 0,
            currentCapacity: dict["CurrentCapacity"] as? Int  ?? 0,
            isCharging:      dict["IsCharging"]      as? Bool ?? false,
            isFullyCharged:  dict["FullyCharged"]    as? Bool ?? false,
            temperature:     Double(dict["Temperature"] as? Int ?? 0) / 100.0,
            timeRemaining:   dict["TimeRemaining"]   as? Int  ?? -1,
            amperage:        dict["Amperage"]        as? Int  ?? 0,
            voltage:         dict["Voltage"]         as? Int  ?? 0
        )
    }
}

// MARK: - Section View

struct BatterySection: View {
    @ObservedObject var vm: BatteryViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Group {
                if vm.isLoading {
                    loadingState
                } else if let info = vm.info {
                    batteryContent(info)
                } else {
                    noBatteryState
                }
            }
        }
        .onAppear { Task { await vm.load() } }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Batterie").font(.callout.weight(.semibold))
                if let info = vm.info {
                    Text("\(info.cycleCount) cycles · \(info.healthLabel)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Santé et état de la batterie")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if vm.isLoading { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.load() } } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered).disabled(vm.isLoading)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().scaleEffect(1.3)
            Text("Lecture de la batterie…").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var noBatteryState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "desktopcomputer")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(Color.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text("Pas de batterie détectée").font(.title3.bold())
                Text("Ce Mac est un modèle fixe (Mac mini, Mac Studio, iMac ou Mac Pro).")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(32)
    }

    @ViewBuilder
    private func batteryContent(_ info: BatteryInfo) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                healthCard(info)
                chargeCard(info)
                detailsCard(info)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func healthCard(_ info: BatteryInfo) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 10)
                    .frame(width: 90, height: 90)
                Circle()
                    .trim(from: 0, to: info.healthPercent)
                    .stroke(info.healthColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int(info.healthPercent * 100))%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("santé").font(.caption2).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("État de la batterie").font(.callout.weight(.semibold))
                    Label(info.healthLabel, systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(info.healthColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capacité actuelle").font(.caption).foregroundStyle(.secondary)
                    Text("\(info.maxCapacity) / \(info.designCapacity) mAh")
                        .font(.callout.monospacedDigit())
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func chargeCard(_ info: BatteryInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Charge actuelle",
                      systemImage: info.isCharging ? "bolt.fill" : "battery.75")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(info.timeRemainingString)
                    .font(.callout).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.1))
                    Capsule()
                        .fill(chargeColor(info))
                        .frame(width: max(4, geo.size.width * info.chargePercent))
                }
            }
            .frame(height: 8)
            HStack {
                Text("\(Int(info.chargePercent * 100))%")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(chargeColor(info))
                Spacer()
                if info.amperage != 0 {
                    Text(info.isCharging
                         ? String(format: "+%.1f W", info.powerWatts)
                         : String(format: "-%.1f W", info.powerWatts))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private func chargeColor(_ info: BatteryInfo) -> Color {
        if info.isCharging || info.isFullyCharged { return .green }
        if info.chargePercent > 0.4 { return .blue }
        if info.chargePercent > 0.2 { return .orange }
        return .red
    }

    @ViewBuilder
    private func detailsCard(_ info: BatteryInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Détails")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.bottom, 8)

            detailRow("Cycles de charge", value: "\(info.cycleCount)",
                      badge: info.cycleLabel, badgeColor: info.cycleColor)
            Divider().padding(.vertical, 6)
            detailRow("Température", value: String(format: "%.1f °C", info.temperature))
            Divider().padding(.vertical, 6)
            detailRow("Tension", value: String(format: "%.3f V", Double(info.voltage) / 1000.0))
            Divider().padding(.vertical, 6)
            detailRow("Courant",
                      value: "\(abs(info.amperage)) mA \(info.isCharging ? "↑" : "↓")")
        }
        .padding(16)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private func detailRow(_ label: String, value: String,
                            badge: String? = nil, badgeColor: Color = .green) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            if let badge {
                Text(badge).font(.caption2).foregroundStyle(badgeColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(badgeColor.opacity(0.1), in: Capsule())
            }
            Text(value).font(.callout.monospacedDigit())
        }
        .font(.callout)
    }
}
