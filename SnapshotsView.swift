//
//  SnapshotsView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct APFSSnapshot: Identifiable {
    let id = UUID()
    let fullName: String
    let dateKey: String     // e.g. "2024-01-15-120000"
    let date: Date?
    var isSelected: Bool = false

    static func parse(_ line: String) -> APFSSnapshot? {
        let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        // Extract date pattern from name
        if let range = name.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) {
            let dateKey = String(name[range])
            return APFSSnapshot(fullName: name, dateKey: dateKey, date: df.date(from: dateKey))
        }
        return APFSSnapshot(fullName: name, dateKey: name, date: nil)
    }

    var formattedDate: String {
        guard let d = date else { return dateKey }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .long; f.timeStyle = .short
        return f.string(from: d)
    }

    var ageString: String {
        guard let d = date else { return "" }
        let days = Int(Date().timeIntervalSince(d) / 86400)
        if days == 0 { return "aujourd'hui" }
        if days == 1 { return "hier" }
        if days < 30 { return "il y a \(days) jour\(days > 1 ? "s" : "")" }
        if days < 365 { return "il y a \(days / 30) mois" }
        return "il y a \(days / 365) an\(days / 365 > 1 ? "s" : "")"
    }
}

// MARK: - ViewModel

@MainActor
class SnapshotsViewModel: ObservableObject {
    @Published var snapshots: [APFSSnapshot] = []
    @Published var isLoading = false
    @Published var isDeleting = false
    @Published var showDeleteConfirm = false
    @Published var showResult = false
    @Published var deletedCount = 0
    @Published var hasLoaded = false
    @Published var deleteError: String? = nil

    var selectedSnapshots: [APFSSnapshot] { snapshots.filter(\.isSelected) }

    func load() async {
        isLoading = true; hasLoaded = true
        defer { isLoading = false }
        let result = await Task.detached(priority: .userInitiated) {
            SnapshotsViewModel.listSnapshots()
        }.value
        withAnimation { snapshots = result }
    }

    func setSelectAll(_ value: Bool) {
        withAnimation { for i in snapshots.indices { snapshots[i].isSelected = value } }
    }

    func deleteSelected() async {
        guard !isDeleting else { return }
        isDeleting = true; defer { isDeleting = false }
        let toDelete = selectedSnapshots
        var succeeded = 0
        var failedKeys = Set<String>()
        for snap in toDelete {
            let ok = await Task.detached(priority: .userInitiated) {
                SnapshotsViewModel.deleteSnapshot(dateKey: snap.dateKey)
            }.value
            if ok { succeeded += 1 } else { failedKeys.insert(snap.dateKey) }
        }
        deletedCount = succeeded
        withAnimation { snapshots.removeAll { $0.isSelected && !failedKeys.contains($0.dateKey) } }
        if succeeded > 0 { showResult = true }
        if !failedKeys.isEmpty {
            deleteError = "Impossible de supprimer \(failedKeys.count) snapshot\(failedKeys.count > 1 ? "s" : ""). Essayez via Terminal avec les droits admin."
        }
    }

    nonisolated static func listSnapshots() -> [APFSSnapshot] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        proc.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.components(separatedBy: "\n").compactMap { APFSSnapshot.parse($0) }
    }

    nonisolated static func deleteSnapshot(dateKey: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        proc.arguments = ["deletelocalsnapshots", dateKey]
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
}

// MARK: - Section View

struct SnapshotsSection: View {
    @ObservedObject var vm: SnapshotsViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isLoading { loadingState }
            else if vm.snapshots.isEmpty { emptyState }
            else { snapshotList; Divider(); footer }
        }
        .onAppear { Task { await vm.load() } }
        .confirmationDialog(
            "Supprimer \(vm.selectedSnapshots.count) snapshot\(vm.selectedSnapshots.count > 1 ? "s" : "") ?",
            isPresented: $vm.showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Supprimer définitivement", role: .destructive) { Task { await vm.deleteSelected() } }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Les snapshots supprimés ne peuvent pas être restaurés.")
        }
        .alert("Snapshots supprimés", isPresented: $vm.showResult) { Button("OK") { } } message: {
            Text("\(vm.deletedCount) snapshot\(vm.deletedCount > 1 ? "s" : "") supprimé\(vm.deletedCount > 1 ? "s" : "").")
        }
        .alert("Erreur", isPresented: .init(get: { vm.deleteError != nil }, set: { if !$0 { vm.deleteError = nil } })) {
            Button("OK") { vm.deleteError = nil }
        } message: {
            Text(vm.deleteError ?? "")
        }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Snapshots APFS").font(.callout.weight(.semibold))
                Text("Instantanés Time Machine locaux créés silencieusement par macOS")
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
            Text("Recherche des snapshots…").foregroundStyle(.secondary); Spacer() }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: vm.hasLoaded ? "checkmark.circle.fill" : "camera.fill")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(vm.hasLoaded ? Color.green.opacity(0.6) : Color.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text(vm.hasLoaded ? "Aucun snapshot local" : "Snapshots APFS")
                    .font(.title3.bold())
                Text(vm.hasLoaded
                     ? "Votre Mac ne contient aucun snapshot Time Machine local en ce moment."
                     : "macOS crée des snapshots invisibles qui peuvent occuper plusieurs Go.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(32)
    }

    private var snapshotList: some View {
        ScrollView {
            VStack(spacing: 10) {
                infoCard
                LazyVStack(spacing: 5) {
                    ForEach($vm.snapshots) { $snap in SnapshotRow(snapshot: $snap) }
                }
            }
            .padding(12)
        }
    }

    private var infoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill").foregroundStyle(.secondary).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("À propos des snapshots APFS").font(.callout.weight(.medium))
                Text("macOS crée automatiquement ces instantanés pour Time Machine et la restauration. Supprimer les anciens libère de l'espace disque réel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
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
            Text("\(vm.snapshots.count) snapshot\(vm.snapshots.count > 1 ? "s" : "")")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            if vm.isDeleting {
                HStack(spacing: 6) { ProgressView().scaleEffect(0.75); Text("Suppression…").font(.callout).foregroundStyle(.secondary) }
            }
            Button { vm.showDeleteConfirm = true } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(Color(red: 0.6, green: 0.25, blue: 0.9)).controlSize(.large)
            .disabled(vm.selectedSnapshots.isEmpty || vm.isDeleting)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Snapshot Row

struct SnapshotRow: View {
    @Binding var snapshot: APFSSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: snapshot.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(snapshot.isSelected ? Color(red: 0.6, green: 0.25, blue: 0.9) : Color.secondary)
                .frame(width: 24)

            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.6, green: 0.25, blue: 0.9).opacity(0.1)).frame(width: 36, height: 36)
                Image(systemName: "camera.fill").font(.system(size: 14)).foregroundStyle(Color(red: 0.6, green: 0.25, blue: 0.9))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.formattedDate).font(.body.weight(.medium))
                Text(snapshot.fullName).font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer()

            Text(snapshot.ageString).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.08), in: Capsule())
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(snapshot.isSelected ? Color(red: 0.6, green: 0.25, blue: 0.9).opacity(0.07) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(snapshot.isSelected ? Color(red: 0.6, green: 0.25, blue: 0.9).opacity(0.3) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3)) { snapshot.isSelected.toggle() } }
    }
}
