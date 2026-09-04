//
//  CrashReportsView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct CrashReport: Identifiable {
    let id = UUID()
    let url: URL
    let sizeBytes: Int64
    let date: Date?
    var isSelected: Bool = false

    var name: String { url.lastPathComponent }
    var ext: String { url.pathExtension.lowercased() }

    var typeIcon: String {
        switch ext {
        case "crash": return "exclamationmark.triangle.fill"
        case "ips":   return "ladybug.fill"
        case "hang":  return "clock.badge.exclamationmark.fill"
        case "spin":  return "arrow.circlepath"
        default:      return "doc.fill"
        }
    }

    var typeColor: Color {
        switch ext {
        case "crash": return .red
        case "ips":   return .orange
        case "hang":  return Color(red: 0.8, green: 0.4, blue: 0.0)
        default:      return .secondary
        }
    }

    var ageString: String {
        guard let d = date else { return "" }
        let days = Int(Date().timeIntervalSince(d) / 86400)
        if days == 0 { return "aujourd'hui" }
        if days == 1 { return "hier" }
        if days < 30 { return "il y a \(days)j" }
        if days < 365 { return "il y a \(days / 30) mois" }
        return "il y a \(days / 365) an\(days / 365 > 1 ? "s" : "")"
    }
}

// MARK: - ViewModel

@MainActor
class CrashReportsViewModel: ObservableObject {
    @Published var reports: [CrashReport] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var isDeleting = false
    @Published var showDeleteConfirm = false
    @Published var showResult = false
    @Published var freedBytes: Int64 = 0

    var selected: [CrashReport] { reports.filter(\.isSelected) }
    var totalSelectedBytes: Int64 { selected.reduce(0) { $0 + $1.sizeBytes } }
    var totalBytes: Int64 { reports.reduce(0) { $0 + $1.sizeBytes } }

    func scan() async {
        isScanning = true; hasScanned = true
        defer { isScanning = false }
        let result = await Task.detached(priority: .userInitiated) {
            CrashReportsViewModel.findReports()
        }.value
        withAnimation { reports = result }
    }

    func setSelectAll(_ value: Bool) {
        for i in reports.indices { reports[i].isSelected = value }
    }

    func deleteSelected() async {
        guard !isDeleting else { return }
        isDeleting = true; defer { isDeleting = false }
        var freed: Int64 = 0
        let toDelete = selected
        for r in toDelete {
            freed += r.sizeBytes
            try? FileManager.default.trashItem(at: r.url, resultingItemURL: nil)
        }
        freedBytes = freed
        let deleted = Set(toDelete.map { $0.url.path })
        withAnimation { reports.removeAll { deleted.contains($0.url.path) } }
        showResult = true
    }

    func reveal(_ r: CrashReport) {
        NSWorkspace.shared.activateFileViewerSelecting([r.url])
    }

    nonisolated static func findReports() -> [CrashReport] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let extensions: Set<String> = ["crash", "ips", "hang", "spin", "diag", "log"]

        let dirs: [URL] = [
            home.appendingPathComponent("Library/Logs/DiagnosticReports"),
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"),
            home.appendingPathComponent("Library/Logs"),
            URL(fileURLWithPath: "/Library/Logs"),
        ]

        var results: [CrashReport] = []
        var seen = Set<String>()

        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .isRegularFileKey]
            ) else { continue }

            for entry in entries {
                let path = entry.path
                guard !seen.contains(path) else { continue }
                guard extensions.contains(entry.pathExtension.lowercased()) else { continue }
                guard let vals = try? entry.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .isRegularFileKey]),
                      vals.isRegularFile == true else { continue }
                seen.insert(path)
                results.append(CrashReport(
                    url: entry,
                    sizeBytes: Int64(vals.fileSize ?? 0),
                    date: vals.creationDate))
            }
        }

        return results.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

// MARK: - Section View

struct CrashReportsSection: View {
    @ObservedObject var vm: CrashReportsViewModel
    private let accent = Color(red: 0.88, green: 0.35, blue: 0.15)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isScanning { loadingState }
            else if !vm.hasScanned { idleState }
            else if vm.reports.isEmpty { emptyState }
            else { reportList; Divider(); footer }
        }
        .onAppear { Task { await vm.scan() } }
        .confirmationDialog(
            "Déplacer \(vm.selected.count) rapport\(vm.selected.count > 1 ? "s" : "") vers la Corbeille ?",
            isPresented: $vm.showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Déplacer vers la Corbeille", role: .destructive) { Task { await vm.deleteSelected() } }
            Button("Annuler", role: .cancel) { }
        } message: { Text("Ces journaux de diagnostics sont inutiles une fois l'application corrigée.") }
        .alert("Nettoyage terminé", isPresented: $vm.showResult) { Button("OK") { } } message: {
            Text("\(vm.freedBytes.formattedSize) de rapports de crash supprimés.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rapports de crash").font(.callout.weight(.semibold))
                Text("\(vm.reports.count) rapport\(vm.reports.count != 1 ? "s" : "") · \(vm.totalBytes.formattedSize)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isScanning { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.scan() } } label: {
                Label("Analyser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered).disabled(vm.isScanning)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var loadingState: some View {
        VStack(spacing: 14) { Spacer(); ProgressView().scaleEffect(1.3)
            Text("Recherche des rapports de crash…").foregroundStyle(.secondary); Spacer() }
    }

    private var idleState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "ladybug.fill")
                .font(.system(size: 60, weight: .thin)).foregroundStyle(accent.opacity(0.6))
            VStack(spacing: 6) {
                Text("Rapports de crash & logs").font(.title3.bold())
                Text("macOS accumule silencieusement des centaines de rapports. Ils sont inutiles une fois le crash passé.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }.padding(32)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60, weight: .thin)).foregroundStyle(Color.green.opacity(0.6))
            Text("Aucun rapport trouvé").font(.title3.bold())
            Spacer()
        }.padding(32)
    }

    private var reportList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach($vm.reports) { $r in
                    CrashReportRow(report: $r)
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Tout sélectionner")   { vm.setSelectAll(true) }
                Button("Tout désélectionner") { vm.setSelectAll(false) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).fixedSize()
            Text("\(vm.reports.count) rapport\(vm.reports.count > 1 ? "s" : "") · \(vm.totalBytes.formattedSize)")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            if vm.isDeleting { ProgressView().scaleEffect(0.75) }
            if vm.totalSelectedBytes > 0 {
                Text("\(vm.totalSelectedBytes.formattedSize)").font(.callout.monospacedDigit().weight(.semibold))
            }
            Button { vm.showDeleteConfirm = true } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
            .disabled(vm.selected.isEmpty || vm.isDeleting)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

struct CrashReportRow: View {
    @Binding var report: CrashReport

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: report.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(report.isSelected ? report.typeColor : Color.secondary)
                .frame(width: 24)

            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(report.typeColor.opacity(0.1)).frame(width: 36, height: 36)
                Image(systemName: report.typeIcon).font(.system(size: 14)).foregroundStyle(report.typeColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(report.name).font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                if !report.ageString.isEmpty {
                    Text(report.ageString).font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(report.sizeBytes.formattedSize)
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(report.isSelected ? report.typeColor.opacity(0.07) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(report.isSelected ? report.typeColor.opacity(0.25) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3)) { report.isSelected.toggle() } }
    }
}
