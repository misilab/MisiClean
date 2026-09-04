//
//  HistoryView.swift
//  MisiClean
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

struct HistorySection: View {
    @ObservedObject private var hm = HistoryManager.shared
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if hm.events.isEmpty { emptyState }
            else { eventList }
        }
        .confirmationDialog("Effacer tout l'historique ?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Effacer", role: .destructive) { withAnimation { hm.clearAll() } }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Cette action est irréversible.")
        }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Historique des nettoyages").font(.callout.weight(.semibold))
                if !hm.events.isEmpty {
                    Text("\(hm.cleanCount) nettoyage\(hm.cleanCount > 1 ? "s" : "") · \(hm.totalFreedBytes.formattedSize) libérés au total")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !hm.events.isEmpty {
                Button { exportHistory() } label: {
                    Label("Exporter", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) { showClearConfirm = true } label: {
                    Label("Effacer tout", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func exportHistory() {
        let cal = Calendar.current
        var lines: [String] = [
            "MisiClean — Rapport d'historique",
            "Généré le \(Date().formatted(date: .long, time: .shortened))",
            "",
            "Total : \(hm.totalFreedBytes.formattedSize) libérés en \(hm.cleanCount) nettoyage\(hm.cleanCount > 1 ? "s" : "")",
            String(repeating: "─", count: 52),
        ]
        let grouped = Dictionary(grouping: hm.events) { e -> String in
            if cal.isDateInToday(e.date) { return "Aujourd'hui" }
            if cal.isDateInYesterday(e.date) { return "Hier" }
            return e.date.formatted(date: .abbreviated, time: .omitted)
        }
        let sortedKeys = grouped.keys.sorted { a, b in
            grouped[a]!.first!.date > grouped[b]!.first!.date
        }
        for key in sortedKeys {
            lines.append(""); lines.append("  \(key)")
            for e in (grouped[key] ?? []).sorted(by: { $0.date > $1.date }) {
                let time = e.date.formatted(date: .omitted, time: .shortened)
                lines.append("  • \(e.freedBytes.formattedSize) libérés à \(time)")
                if !e.categoryNames.isEmpty {
                    lines.append("    \(e.categoryNames.joined(separator: " · "))")
                }
            }
        }
        let content = lines.joined(separator: "\n")

        let panel = NSSavePanel()
        panel.title = "Exporter l'historique"
        panel.nameFieldStringValue = "MisiClean-historique.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text("Aucun nettoyage enregistré").font(.title3.bold())
                Text("Chaque nettoyage effectué sera consigné ici\navec la date et l'espace libéré.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    private var eventList: some View {
        ScrollView {
            // Group by day
            let grouped = Dictionary(grouping: hm.events) { event -> String in
                let cal = Calendar.current
                if cal.isDateInToday(event.date) { return "Aujourd'hui" }
                if cal.isDateInYesterday(event.date) { return "Hier" }
                return event.date.formatted(date: .abbreviated, time: .omitted)
            }
            let sortedKeys = grouped.keys.sorted { a, b in
                let dateA = grouped[a]!.first!.date
                let dateB = grouped[b]!.first!.date
                return dateA > dateB
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(sortedKeys, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(key)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.leading, 4)
                        ForEach(grouped[key]!) { event in
                            HistoryEventRow(event: event) {
                                withAnimation { hm.delete(event) }
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

struct HistoryEventRow: View {
    let event: CleanupEvent
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(iconColor.opacity(0.12)).frame(width: 42, height: 42)
                Image(systemName: "sparkles").foregroundStyle(iconColor).font(.system(size: 18, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.freedBytes.formattedSize)
                        .font(.body.weight(.semibold))
                    Text("libérés").font(.body).foregroundStyle(.secondary)
                }
                if !event.categoryNames.isEmpty {
                    Text(event.categoryNames.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            Text(event.date.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.callout).foregroundStyle(.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(iconColor.opacity(0.1), lineWidth: 1))
    }

    private var iconColor: Color {
        if event.freedBytes > 1_000_000_000 { return .red }
        if event.freedBytes > 200_000_000   { return .orange }
        return .green
    }
}
