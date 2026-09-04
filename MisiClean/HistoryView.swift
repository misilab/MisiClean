//
//  HistoryView.swift
//  MisiClean
//

import SwiftUI
import AppKit
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

                Button { exportAsPDF() } label: {
                    Label("PDF", systemImage: "doc.richtext")
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

    private func exportAsPDF() {
        let estimatedHeight = CGFloat(200 + min(hm.events.count, 100) * 34)
        let frame = CGRect(x: 0, y: 0, width: 595, height: max(estimatedHeight, 500))
        let host = NSHostingView(rootView: HistoryPDFContent(
            events: hm.events,
            totalFreed: hm.totalFreedBytes,
            cleanCount: hm.cleanCount
        ))
        host.frame = frame

        let panel = NSSavePanel()
        panel.title = "Exporter le rapport PDF"
        panel.nameFieldStringValue = "MisiClean-rapport.pdf"
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url {
            let data = host.dataWithPDF(inside: frame)
            try? data.write(to: url)
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

// MARK: - PDF Report Content

private struct HistoryPDFContent: View {
    let events: [CleanupEvent]
    let totalFreed: Int64
    let cleanCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MisiClean")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                    Text("Rapport de nettoyage")
                        .font(.title3)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Date().formatted(date: .long, time: .omitted))
                        .font(.callout).foregroundStyle(Color.black)
                    Text(Date().formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(Color.secondary)
                }
            }
            .padding(.bottom, 20)

            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)

            // Summary stats
            HStack(spacing: 0) {
                pdfStatBox(value: totalFreed.formattedSize, label: "Espace libéré")
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 44)
                pdfStatBox(value: "\(cleanCount)", label: "Nettoyage\(cleanCount > 1 ? "s" : "")")
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 44)
                pdfStatBox(value: "\(events.count)", label: "Événements")
            }
            .padding(.vertical, 16)

            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)

            // Event table
            Text("Historique détaillé")
                .font(.headline).foregroundStyle(Color.black)
                .padding(.top, 16).padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Date").font(.caption.weight(.semibold)).foregroundStyle(Color.secondary)
                        .frame(width: 140, alignment: .leading)
                    Text("Catégories").font(.caption.weight(.semibold)).foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Libéré").font(.caption.weight(.semibold)).foregroundStyle(Color.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 6).padding(.horizontal, 8)
                .background(Color.secondary.opacity(0.1))

                ForEach(Array(events.prefix(100).enumerated()), id: \.element.id) { idx, event in
                    HStack {
                        Text(event.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption.monospacedDigit()).foregroundStyle(Color.secondary)
                            .frame(width: 140, alignment: .leading)
                        Text(event.categoryNames.isEmpty ? "—" : event.categoryNames.joined(separator: ", "))
                            .font(.caption).lineLimit(1).foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(event.freedBytes.formattedSize)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.blue)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .background(idx.isMultiple(of: 2) ? Color.secondary.opacity(0.04) : Color.clear)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            Spacer(minLength: 40)

            // Footer
            Text("Généré par MisiClean · \(Date().formatted(date: .long, time: .shortened))")
                .font(.system(size: 9)).foregroundStyle(Color.secondary)
        }
        .padding(40)
        .background(Color.white)
        .frame(width: 595)
    }

    private func pdfStatBox(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(Color.black)
            Text(label).font(.caption).foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
