//
//  AppUninstallerView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - ViewModel

@MainActor
class AppUninstallerViewModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var showConfirm = false
    @Published var confirmMode: UninstallMode = .full
    @Published var showResult = false
    @Published var resultMessage = ""
    @Published var hasLoaded = false

    enum UninstallMode { case full, leftoversOnly }

    enum AppFilter: String, CaseIterable, Identifiable {
        case all      = "Toutes"
        case unused6m = "> 6 mois"
        case unused1y = "> 1 an"
        var id: String { rawValue }
    }

    @Published var appFilter: AppFilter = .all

    var filtered: [InstalledApp] {
        let base = searchText.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        switch appFilter {
        case .all: return base
        case .unused6m:
            let threshold6m = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
            return base.filter { $0.lastUsedDate.map { $0 < threshold6m } ?? true }
        case .unused1y:
            let threshold1y = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date()
            return base.filter { $0.lastUsedDate.map { $0 < threshold1y } ?? true }
        }
    }
    var selectedApps: [InstalledApp] { apps.filter(\.isSelected) }
    var totalLeftoverBytes: Int64 { selectedApps.reduce(0) { $0 + $1.leftoverBytes } }
    var hasSelectedLeftovers: Bool { selectedApps.contains { $0.leftoverBytes > 0 } }

    func loadApps() async {
        guard !isLoading else { return }
        isLoading = true; hasLoaded = true; apps = []
        defer { isLoading = false }

        let discovered = await Task.detached(priority: .userInitiated) {
            AppUninstallerViewModel.discoverApps()
        }.value
        apps = discovered

        await withTaskGroup(of: (Int, [URL], Int64, Int64).self) { group in
            for (i, app) in apps.enumerated() {
                group.addTask { [app] in
                    let leftovers = app.bundleID.isEmpty ? [] : AppUninstallerViewModel.findLeftovers(for: app.bundleID)
                    let leftoverSize = leftovers.reduce(0) { $0 + AppUninstallerViewModel.itemSize($1) }
                    let appSize = AppUninstallerViewModel.itemSize(app.url)
                    return (i, leftovers, leftoverSize, appSize)
                }
            }
            for await (i, leftovers, leftoverSize, appSize) in group {
                guard i < apps.count else { continue }
                apps[i].leftovers = leftovers
                apps[i].leftoverBytes = leftoverSize
                apps[i].appSizeBytes = appSize
                apps[i].isLoadingLeftovers = false
            }
        }

        withAnimation {
            apps.sort {
                if $0.leftoverBytes != $1.leftoverBytes { return $0.leftoverBytes > $1.leftoverBytes }
                return $0.name < $1.name
            }
        }
    }

    nonisolated static func discoverApps() -> [InstalledApp] {
        let fm = FileManager.default
        let dirs = [URL(fileURLWithPath: "/Applications"),
                    fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var result: [InstalledApp] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.pathExtension == "app" {
                let infoPlist = item.appendingPathComponent("Contents/Info.plist")
                var bundleID = ""; var version = ""
                if let dict = NSDictionary(contentsOf: infoPlist) as? [String: Any] {
                    bundleID = dict["CFBundleIdentifier"] as? String ?? ""
                    version  = dict["CFBundleShortVersionString"] as? String ?? ""
                }
                var app = InstalledApp(url: item, bundleID: bundleID, version: version)
                if let mdItem = NSMetadataItem(url: item) {
                    app.lastUsedDate = mdItem.value(forAttribute: "kMDItemLastUsedDate") as? Date
                }
                result.append(app)
            }
        }
        return result
    }

    nonisolated static func findLeftovers(for bundleID: String) -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let lib  = home.appendingPathComponent("Library")

        var candidates: [URL] = [
            lib.appendingPathComponent("Application Support/\(bundleID)"),
            lib.appendingPathComponent("Caches/\(bundleID)"),
            lib.appendingPathComponent("Preferences/\(bundleID).plist"),
            lib.appendingPathComponent("Containers/\(bundleID)"),
            lib.appendingPathComponent("Application Scripts/\(bundleID)"),
            lib.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
            lib.appendingPathComponent("WebKit/\(bundleID)"),
            lib.appendingPathComponent("HTTPStorages/\(bundleID)"),
            lib.appendingPathComponent("Logs/\(bundleID)"),
            lib.appendingPathComponent("Cookies/\(bundleID).binarycookies"),
        ]

        // Group Containers — souvent la plus grande source de restes
        let gcDir = lib.appendingPathComponent("Group Containers")
        if let gcItems = try? fm.contentsOfDirectory(at: gcDir, includingPropertiesForKeys: nil) {
            for item in gcItems where item.lastPathComponent.contains(bundleID) {
                candidates.append(item)
            }
        }

        return candidates.filter { fm.fileExists(atPath: $0.path) }
    }

    nonisolated static func itemSize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        if let v = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
           v.isRegularFile == true { return Int64(v.fileSize ?? 0) }
        var size: Int64 = 0
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            size += Int64(v.fileSize ?? 0)
        }
        return size
    }

    func toggleSelection(for id: InstalledApp.ID) {
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.25)) { apps[i].isSelected.toggle() }
    }

    // Désinstalle app + traces
    func deleteSelected() async {
        let toDelete = selectedApps
        for app in toDelete {
            try? FileManager.default.trashItem(at: app.url, resultingItemURL: nil)
            for leftover in app.leftovers {
                try? FileManager.default.trashItem(at: leftover, resultingItemURL: nil)
            }
        }
        resultMessage = "\(toDelete.count) application\(toDelete.count > 1 ? "s" : "") déplacée\(toDelete.count > 1 ? "s" : "") vers la Corbeille."
        withAnimation { apps.removeAll { $0.isSelected } }
        showResult = true
    }

    // Supprime uniquement les traces, garde l'app
    func deleteLeftoversOnly() async {
        let targets = selectedApps.filter { $0.leftoverBytes > 0 }
        var totalFreed: Int64 = 0
        for app in targets {
            totalFreed += app.leftoverBytes
            for leftover in app.leftovers {
                try? FileManager.default.trashItem(at: leftover, resultingItemURL: nil)
            }
        }
        withAnimation {
            for i in apps.indices where apps[i].isSelected {
                apps[i].leftovers = []
                apps[i].leftoverBytes = 0
                apps[i].isSelected = false
            }
        }
        resultMessage = "\(totalFreed.formattedSize) de traces supprimés · les applications sont conservées."
        showResult = true
    }

    func revealInFinder(_ app: InstalledApp) {
        NSWorkspace.shared.selectFile(app.url.path, inFileViewerRootedAtPath: "")
    }
}

// MARK: - Section

struct AppUninstallerSection: View {
    @ObservedObject var vm: AppUninstallerViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isLoading && vm.apps.isEmpty { loadingState }
            else if !vm.hasLoaded { emptyState }
            else if vm.filtered.isEmpty { noResultsState }
            else { appList; Divider(); footer }
        }
        .confirmationDialog(
            vm.confirmMode == .full
                ? "Désinstaller \(vm.selectedApps.count) application\(vm.selectedApps.count > 1 ? "s" : "") ?"
                : "Supprimer les traces de \(vm.selectedApps.count) application\(vm.selectedApps.count > 1 ? "s" : "") ?",
            isPresented: $vm.showConfirm, titleVisibility: .visible
        ) {
            if vm.confirmMode == .full {
                Button("Désinstaller (app + traces)", role: .destructive) {
                    Task { await vm.deleteSelected() }
                }
            } else {
                Button("Supprimer les traces seulement", role: .destructive) {
                    Task { await vm.deleteLeftoversOnly() }
                }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text(vm.confirmMode == .full
                 ? "L'application et tous ses fichiers résiduels seront déplacés vers la Corbeille."
                 : "Les préférences, caches et conteneurs seront supprimés. L'application restera intacte.")
        }
        .alert("Terminé", isPresented: $vm.showResult) {
            Button("OK") { }
        } message: { Text(vm.resultMessage) }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher une application…", text: $vm.searchText).textFieldStyle(.plain)
            Picker("", selection: $vm.appFilter) {
                ForEach(AppUninstallerViewModel.AppFilter.allCases) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            .help("Filtrer par dernière utilisation")
            Spacer()
            Button { Task { await vm.loadApps() } } label: {
                Label(vm.isLoading ? "Chargement…" : "Analyser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isLoading)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().scaleEffect(1.3)
            Text("Analyse des applications et fichiers résiduels…").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "trash.circle").font(.system(size: 60, weight: .thin)).foregroundStyle(.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text("Désinstalleur d'applications").font(.title3.bold())
                Text("Supprimez les applications et toutes leurs traces\n(préférences, caches, conteneurs, Group Containers).")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    private var noResultsState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.system(size: 40, weight: .thin)).foregroundStyle(.secondary.opacity(0.4))
            Text("Aucun résultat pour « \(vm.searchText) »").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(vm.filtered) { app in
                    AppRow(app: app, onReveal: { vm.revealInFinder(app) }) {
                        vm.toggleSelection(for: app.id)
                    }
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Group {
                if vm.appFilter == .all {
                    Text("\(vm.apps.count) application\(vm.apps.count > 1 ? "s" : "")")
                } else {
                    Text("\(vm.filtered.count) / \(vm.apps.count) application\(vm.apps.count > 1 ? "s" : "")")
                }
            }
            .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            if !vm.selectedApps.isEmpty {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(vm.selectedApps.count) sélectionnée\(vm.selectedApps.count > 1 ? "s" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                    if vm.totalLeftoverBytes > 0 {
                        Text("\(vm.totalLeftoverBytes.formattedSize) de traces")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
                .transition(.opacity)
            }
            // Traces seulement
            if vm.hasSelectedLeftovers {
                Button {
                    vm.confirmMode = .leftoversOnly
                    vm.showConfirm = true
                } label: {
                    Label("Traces seules", systemImage: "eraser.fill")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .help("Supprime les restes sans toucher à l'application")
                .disabled(vm.selectedApps.isEmpty)
            }
            // Désinstallation complète
            Button {
                vm.confirmMode = .full
                vm.showConfirm = true
            } label: {
                Label("Désinstaller", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(vm.selectedApps.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - App Row

struct AppRow: View {
    let app: InstalledApp
    let onReveal: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: app.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(app.isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.body.weight(.medium))
                    if !app.version.isEmpty {
                        Text("v\(app.version)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Text(app.url.deletingLastPathComponent().path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if let used = app.lastUsedDate {
                    Text("Utilisée \(used.relativeFormatted)")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text("Jamais ouverte")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if app.isLoadingLeftovers {
                ProgressView().scaleEffect(0.6).frame(width: 100)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(app.appSizeBytes.formattedSize)
                        .font(.callout.monospacedDigit().weight(.medium))
                    if app.leftoverBytes > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle.fill").font(.caption2)
                            Text("\(app.leftoverBytes.formattedSize) traces")
                                .font(.caption)
                        }
                        .foregroundStyle(.orange)
                    } else if app.appSizeBytes > 0 {
                        Text("Propre").font(.caption).foregroundStyle(.green)
                    }
                }
                .frame(minWidth: 110, alignment: .trailing)
            }

            Button(action: onReveal) {
                Image(systemName: "folder").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Afficher dans le Finder")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(app.isSelected ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(app.isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
