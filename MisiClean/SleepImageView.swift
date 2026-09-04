//
//  SleepImageView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct VirtualMemoryInfo {
    let sleepImageSize: Int64
    let swapFiles: [(url: URL, size: Int64)]
    let hibernateMode: Int

    var swapTotal: Int64 { swapFiles.reduce(0) { $0 + $1.size } }
    var total: Int64 { sleepImageSize + swapTotal }

    var hibernateModeDescription: String {
        switch hibernateMode {
        case 0:  return "Désactivé (RAM seule — pas de sleepimage)"
        case 3:  return "Mode hybride (défaut MacBook — safe sleep)"
        case 25: return "Hibernation complète (image requise)"
        default: return "Mode \(hibernateMode)"
        }
    }
}

// MARK: - ViewModel

@MainActor
class SleepImageViewModel: ObservableObject {
    @Published var info: VirtualMemoryInfo?
    @Published var isLoading = false
    @Published var copiedCommand: String? = nil

    func load() async {
        isLoading = true; defer { isLoading = false }
        let result = await Task.detached(priority: .userInitiated) {
            SleepImageViewModel.readInfo()
        }.value
        info = result
    }

    func copyCommand(_ cmd: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        copiedCommand = cmd
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copiedCommand = nil
        }
    }

    nonisolated static func readInfo() -> VirtualMemoryInfo {
        let fm = FileManager.default
        let vmDir = URL(fileURLWithPath: "/private/var/vm")

        // Sleep image size
        let sleepImage = vmDir.appendingPathComponent("sleepimage")
        let sleepSize: Int64
        if let attrs = try? fm.attributesOfItem(atPath: sleepImage.path),
           let size = attrs[.size] as? Int64 {
            sleepSize = size
        } else { sleepSize = 0 }

        // Swap files
        var swapFiles: [(url: URL, size: Int64)] = []
        if let entries = try? fm.contentsOfDirectory(at: vmDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for entry in entries where entry.lastPathComponent.hasPrefix("swapfile") {
                if let attrs = try? fm.attributesOfItem(atPath: entry.path),
                   let size = attrs[.size] as? Int64 {
                    swapFiles.append((url: entry, size: size))
                }
            }
        }
        swapFiles.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }

        // Hibernate mode via pmset
        let mode = readHibernateMode()

        return VirtualMemoryInfo(sleepImageSize: sleepSize, swapFiles: swapFiles, hibernateMode: mode)
    }

    nonisolated private static func readHibernateMode() -> Int {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["-g"]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return -1 }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in out.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            if parts.first == "hibernatemode", let val = parts.last, let mode = Int(val) {
                return mode
            }
        }
        return -1
    }
}

// MARK: - Section View

struct SleepImageSection: View {
    @ObservedObject var vm: SleepImageViewModel
    private let accent = Color(red: 0.3, green: 0.45, blue: 0.85)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isLoading { loadingState }
            else if let info = vm.info { content(info) }
            else { loadingState }
        }
        .onAppear { Task { await vm.load() } }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mémoire virtuelle").font(.callout.weight(.semibold))
                if let info = vm.info {
                    Text("Sleep image + swap · \(info.total.formattedSize)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Sleep image & swap files").font(.caption).foregroundStyle(.secondary)
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
        VStack(spacing: 14) { Spacer(); ProgressView().scaleEffect(1.3)
            Text("Lecture de la mémoire virtuelle…").foregroundStyle(.secondary); Spacer() }
    }

    @ViewBuilder
    private func content(_ info: VirtualMemoryInfo) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                // Overview card
                overviewCard(info)

                // Sleep image card
                sleepImageCard(info)

                // Swap card
                if !info.swapFiles.isEmpty {
                    swapCard(info)
                }

                // Commands card
                commandsCard(info)
            }
            .padding(16)
        }
    }

    private func overviewCard(_ info: VirtualMemoryInfo) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 8).frame(width: 70, height: 70)
                Circle()
                    .trim(from: 0, to: info.sleepImageSize > 0 ? 1.0 : 0)
                    .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 16)).foregroundStyle(accent)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode hibernation").font(.callout.weight(.semibold))
                    Text(info.hibernateModeDescription)
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Espace total occupé").font(.caption).foregroundStyle(.secondary)
                    Text(info.total.formattedSize)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(info.total > 8_000_000_000 ? .red : accent)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sleepImageCard(_ info: VirtualMemoryInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Sleep image", systemImage: "moon.fill")
                    .font(.callout.weight(.semibold))
                Spacer()
                if info.sleepImageSize > 0 {
                    Text(info.sleepImageSize.formattedSize)
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(info.sleepImageSize > 8_000_000_000 ? .red : .orange)
                } else {
                    Text("Absent").font(.caption).foregroundStyle(.green)
                }
            }
            .padding(16)

            Divider().padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("Qu'est-ce que c'est ?")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("macOS copie le contenu entier de la RAM vers ce fichier lors de la mise en veille prolongée. Sa taille est exactement égale à la RAM installée. Il se recrée automatiquement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func swapCard(_ info: VirtualMemoryInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Swap files (\(info.swapFiles.count))", systemImage: "arrow.left.arrow.right.circle.fill")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(info.swapTotal.formattedSize)
                    .font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(16)

            ForEach(Array(info.swapFiles.enumerated()), id: \.offset) { _, swap in
                Divider().padding(.horizontal, 16)
                HStack {
                    Text(swap.url.lastPathComponent)
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Text(swap.size.formattedSize).font(.caption.monospacedDigit())
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private func commandsCard(_ info: VirtualMemoryInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Libérer de l'espace (Terminal requis)", systemImage: "terminal.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            if info.hibernateMode != 0 {
                commandRow(
                    title: "Désactiver la sleep image",
                    subtitle: "Supprime /private/var/vm/sleepimage (\(info.sleepImageSize.formattedSize)). La mise en veille sera légèrement moins sûre.",
                    command: "sudo pmset -a hibernatemode 0 && sudo rm -f /private/var/vm/sleepimage"
                )
            }

            commandRow(
                title: "Re-activer (si besoin)",
                subtitle: "Restaure le mode hybride par défaut des MacBook.",
                command: "sudo pmset -a hibernatemode 3"
            )
        }
        .padding(16)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private func commandRow(title: String, subtitle: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.medium))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                Button {
                    vm.copyCommand(command)
                } label: {
                    Image(systemName: vm.copiedCommand == command ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(vm.copiedCommand == command ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copier la commande")
            }
        }
    }
}
