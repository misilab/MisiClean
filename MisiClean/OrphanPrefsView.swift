import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct OrphanPref: Identifiable {
    let id: UUID
    let url: URL
    let sizeBytes: Int64
    var isSelected: Bool

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    var filename: String { url.lastPathComponent }
    var bundleID: String { url.deletingPathExtension().lastPathComponent }
    var locationDisplay: String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: Self.home, with: "~")
    }
}

// MARK: - ViewModel

@MainActor
final class OrphanPrefsViewModel: ObservableObject {
    @Published var prefs: [OrphanPref] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var showSystem: Bool = false

    var displayed: [OrphanPref] {
        showSystem ? prefs : prefs.filter { !$0.bundleID.hasPrefix("com.apple.") }
    }

    var totalSelectedBytes: Int64 {
        prefs.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedCount: Int {
        prefs.filter { $0.isSelected }.count
    }

    func scan() async {
        isScanning = true
        prefs = []

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let userPrefs = home.appendingPathComponent("Library/Preferences")
        let systemPrefs = URL(fileURLWithPath: "/Library/Preferences")

        let results: [OrphanPref] = await Task.detached(priority: .userInitiated) {
            var found: [OrphanPref] = []
            let roots = [userPrefs, systemPrefs]

            for root in roots {
                guard fm.fileExists(atPath: root.path) else { continue }
                guard let contents = try? fm.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for url in contents {
                    guard url.pathExtension.lowercased() == "plist" else { continue }
                    let name = url.deletingPathExtension().lastPathComponent
                    // Skip files with no dot in the name (not bundle-ID shaped)
                    guard name.contains(".") else { continue }

                    let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard vals?.isRegularFile == true else { continue }
                    let size = Int64(vals?.fileSize ?? 0)

                    found.append(OrphanPref(id: UUID(), url: url, sizeBytes: size, isSelected: false))
                }
            }
            return found
        }.value

        // Check each candidate on the main actor (NSWorkspace is main-thread bound)
        var orphans: [OrphanPref] = []
        for pref in results {
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: pref.bundleID)
            if app == nil {
                orphans.append(pref)
            }
        }

        prefs = orphans.sorted { $0.sizeBytes > $1.sizeBytes }
        isScanning = false
        hasScanned = true
    }

    func deleteSelected() {
        let fm = FileManager.default
        var remaining: [OrphanPref] = []
        for pref in prefs {
            if pref.isSelected {
                try? fm.trashItem(at: pref.url, resultingItemURL: nil)
            } else {
                remaining.append(pref)
            }
        }
        prefs = remaining
    }

    func toggle(_ id: UUID) {
        if let idx = prefs.firstIndex(where: { $0.id == id }) {
            prefs[idx].isSelected.toggle()
        }
    }

    func setAll(_ on: Bool) {
        for idx in prefs.indices {
            prefs[idx].isSelected = on
        }
    }
}

// MARK: - Main View

private let orphanAccent = Color(red: 0.55, green: 0.28, blue: 0.92)

struct OrphanPrefsSection: View {
    @ObservedObject var vm: OrphanPrefsViewModel

    private var subtitle: String {
        let list = vm.displayed
        let count = list.count
        let total = list.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return "\(count) fichier\(count == 1 ? "" : "s") · \(total.formattedSize)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Préférences orphelines")
                        .font(.title2).bold()
                    if vm.hasScanned {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("Inclure système", isOn: $vm.showSystem)
                    .toggleStyle(.checkbox)
                    .disabled(!vm.hasScanned && !vm.isScanning)
                Button {
                    Task { await vm.scan() }
                } label: {
                    Label("Scanner", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(orphanAccent)
                .disabled(vm.isScanning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // Body
            if vm.isScanning {
                scanningView
            } else if !vm.hasScanned {
                idleView
            } else if vm.displayed.isEmpty {
                emptyView
            } else {
                resultView
            }
        }
    }

    // MARK: - States

    private var idleView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.badge.gearshape.fill")
                .font(.system(size: 56))
                .foregroundStyle(orphanAccent.opacity(0.8))
            Text("Préférences orphelines")
                .font(.title3).bold()
            Text("Détecte les fichiers .plist laissés par des apps désinstallées dans ~/Library/Preferences et /Library/Preferences.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                Task { await vm.scan() }
            } label: {
                Label("Scanner", systemImage: "magnifyingglass")
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(orphanAccent)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
            Text("Analyse en cours…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Aucune préférence orpheline")
                .font(.title3).bold()
            Text("Toutes les préférences correspondent à une app installée.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultView: some View {
        VStack(spacing: 0) {
            List {
                ForEach(vm.displayed) { pref in
                    OrphanPrefRow(pref: pref, accent: orphanAccent) {
                        vm.toggle(pref.id)
                    }
                }
            }
            .listStyle(.inset)

            Divider()
            footer
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Tout sélectionner")  { vm.setAll(true) }
                Button("Tout désélectionner") { vm.setAll(false) }
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if vm.selectedCount > 0 {
                Text("\(vm.selectedCount) sélectionné\(vm.selectedCount > 1 ? "s" : "") · \(vm.totalSelectedBytes.formattedSize)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Sélectionnez des fichiers à supprimer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                vm.deleteSelected()
            } label: {
                Label("Mettre à la Corbeille", systemImage: "trash")
            }
            .disabled(vm.selectedCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Row

private struct OrphanPrefRow: View {
    let pref: OrphanPref
    let accent: Color
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pref.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(pref.isSelected ? accent : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(pref.filename)
                    .font(.callout).bold()
                    .lineLimit(1)
                Text(pref.locationDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(pref.sizeBytes.formattedSize)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .padding(.vertical, 4)
    }
}
