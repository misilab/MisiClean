//
//  MenuBarView.swift
//  MisiClean
//

import SwiftUI
import AppKit

// MARK: - Menu Bar Label

struct MenuBarStatusLabel: View {
    let diskInfo: DiskInfo

    private var freeText: String {
        let gb = Double(diskInfo.availableBytes) / 1_000_000_000
        if gb >= 1 { return String(format: "%.0f Go", gb) }
        let mb = Double(diskInfo.availableBytes) / 1_000_000
        return String(format: "%.0f Mo", mb)
    }

    private var statusColor: Color {
        diskInfo.usedFraction > 0.9 ? .red : diskInfo.usedFraction > 0.75 ? .orange : .primary
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: diskInfo.usedFraction > 0.9 ? "internaldrive.fill" : "internaldrive")
            Text(freeText)
                .font(.caption.monospacedDigit().weight(.medium))
        }
        .foregroundStyle(statusColor)
    }
}

// MARK: - Menu Bar Panel

struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow
    @State private var diskInfo = DiskInfo.load()
    @ObservedObject private var hm = HistoryManager.shared
    @State private var isHoveringOpen = false
    @State private var isHoveringQuit = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            diskSection
            Divider()
            if !hm.events.isEmpty {
                historySnippet
                Divider()
            }
            actions
        }
        .frame(width: 300)
        .onAppear { diskInfo = DiskInfo.load() }
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
            // Disk status indicator dot
            Circle()
                .fill(diskStatusColor)
                .frame(width: 8, height: 8)
                .help(diskStatusLabel)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Disk usage

    private var diskSection: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Disque", systemImage: "internaldrive").font(.callout)
                Spacer()
                Text("\(diskInfo.availableBytes.formattedSize) libres")
                    .font(.caption.monospacedDigit()).foregroundStyle(diskStatusColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [diskStatusColor, diskStatusColor.opacity(0.6)],
                                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * CGFloat(diskInfo.usedFraction)))
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(diskInfo.usedBytes.formattedSize) / \(diskInfo.totalBytes.formattedSize)")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(diskInfo.usedFraction * 100))% utilisé")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
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
            Text("Total: \(hm.totalFreedBytes.formattedSize)")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 2) {
            menuButton(label: "Ouvrir MisiClean", icon: "sparkles", isHovering: isHoveringOpen) {
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
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    // MARK: Helpers

    private var diskStatusColor: Color {
        diskInfo.usedFraction > 0.9 ? .red : diskInfo.usedFraction > 0.75 ? .orange : .green
    }

    private var diskStatusLabel: String {
        diskInfo.usedFraction > 0.9 ? "Disque critique" : diskInfo.usedFraction > 0.75 ? "Espace limité" : "Espace suffisant"
    }
}
