//
//  LoginItemsView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - ViewModel

@MainActor
class LoginItemsViewModel: ObservableObject {
    @Published var items: [LoginItem] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var errorMessage: String? = nil
    @Published var togglingIDs: Set<UUID> = []

    func load() async {
        guard !isLoading else { return }
        isLoading = true; hasLoaded = true
        defer { isLoading = false }
        let result = await Task.detached(priority: .userInitiated) {
            LoginItemsViewModel.discoverLoginItems()
        }.value
        withAnimation { items = result }
    }

    nonisolated static func discoverLoginItems() -> [LoginItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let loaded = loadedLabels()
        var result: [LoginItem] = []

        for (dir, isSystem) in [
            (home.appendingPathComponent("Library/LaunchAgents"), false),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), true),
        ] {
            guard let plistURLs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                    .filter({ $0.pathExtension == "plist" }) else { continue }
            for url in plistURLs {
                if let item = parseLoginItem(url: url, loaded: loaded, isSystem: isSystem) {
                    result.append(item)
                }
            }
        }

        return result.sorted { !$0.isSystem && $1.isSystem
            || ($0.isSystem == $1.isSystem && $0.displayName < $1.displayName) }
    }

    nonisolated static func loadedLabels() -> Set<String> {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["list"]
        let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var labels = Set<String>()
        for line in out.components(separatedBy: "\n").dropFirst() {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 3 { labels.insert(parts[2].trimmingCharacters(in: .whitespaces)) }
        }
        return labels
    }

    nonisolated static func parseLoginItem(url: URL, loaded: Set<String>, isSystem: Bool) -> LoginItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let label = plist["Label"] as? String else { return nil }
        let programPath: String
        if let prog = plist["Program"] as? String { programPath = prog }
        else if let args = plist["ProgramArguments"] as? [String], let first = args.first { programPath = first }
        else { return nil }
        guard !programPath.isEmpty else { return nil }
        return LoginItem(label: label, programPath: programPath, plistURL: url,
                         isEnabled: loaded.contains(label), isSystem: isSystem)
    }

    func toggle(_ item: LoginItem) async {
        guard !togglingIDs.contains(item.id),
              let idx = items.firstIndex(where: { $0.id == item.id }) else { return }

        togglingIDs.insert(item.id)
        defer { togglingIDs.remove(item.id) }

        let newState = !item.isEnabled
        let plistPath = item.plistURL.path
        let (success, errorDetail) = await Task.detached(priority: .userInitiated) {
            LoginItemsViewModel.runLaunchctl(args: [newState ? "load" : "unload", plistPath])
        }.value

        if success {
            withAnimation { items[idx].isEnabled = newState }
        } else {
            errorMessage = "Impossible de \(newState ? "activer" : "désactiver") « \(item.displayName) ».\n\n\(errorDetail)"
        }
    }

    nonisolated static func runLaunchctl(args: [String]) -> (Bool, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        proc.standardOutput = Pipe()
        let errPipe = Pipe(); proc.standardError = errPipe
        guard (try? proc.run()) != nil else { return (false, "Impossible de lancer launchctl.") }
        proc.waitUntilExit()
        let errOut = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (proc.terminationStatus == 0, errOut.isEmpty ? "Vérifiez que le programme existe à son emplacement d'origine." : errOut)
    }

    func revealInFinder(_ item: LoginItem) {
        let path = item.appPath
        NSWorkspace.shared.selectFile(
            FileManager.default.fileExists(atPath: path) ? path : item.programPath,
            inFileViewerRootedAtPath: "")
    }
}

// MARK: - Section

struct LoginItemsSection: View {
    @ObservedObject var vm: LoginItemsViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isLoading { loadingState }
            else if !vm.hasLoaded { emptyState }
            else if vm.items.isEmpty { noItemsState }
            else { itemList }
        }
        .alert("Erreur", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Éléments de démarrage").font(.callout.weight(.semibold))
                Text("Services et agents qui se lancent au démarrage de session")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await vm.load() } } label: {
                Label(vm.isLoading ? "Chargement…" : "Actualiser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isLoading)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var loadingState: some View {
        VStack(spacing: 14) { Spacer(); ProgressView().scaleEffect(1.3)
            Text("Chargement des éléments de démarrage…").foregroundStyle(.secondary); Spacer() }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bolt.circle").font(.system(size: 60, weight: .thin)).foregroundStyle(.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text("Éléments de démarrage").font(.title3.bold())
                Text("Gérez ce qui se lance automatiquement\nlorsque vous démarrez votre Mac.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    private var noItemsState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 60, weight: .thin)).foregroundStyle(Color.green.opacity(0.5))
            Text("Aucun agent de démarrage trouvé").font(.title3.bold())
            Text("~/Library/LaunchAgents et /Library/LaunchAgents sont vides.").foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private var itemList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let userItems = vm.items.filter { !$0.isSystem }
                let sysItems  = vm.items.filter { $0.isSystem }
                if !userItems.isEmpty {
                    sectionHeader("Agents utilisateur (\(userItems.count))")
                    ForEach(userItems) { item in
                        LoginItemRow(item: item, isToggling: vm.togglingIDs.contains(item.id),
                            onToggle: { Task { await vm.toggle(item) } },
                            onReveal: { vm.revealInFinder(item) })
                    }
                }
                if !sysItems.isEmpty {
                    sectionHeader("Agents système (\(sysItems.count)) — lecture seule")
                    ForEach(sysItems) { item in
                        LoginItemRow(item: item, isToggling: false, onToggle: { }, onReveal: { vm.revealInFinder(item) })
                    }
                }
            }
            .padding(12)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .textCase(.uppercase).padding(.top, 4).padding(.leading, 4)
    }
}

// MARK: - Login Item Row

struct LoginItemRow: View {
    let item: LoginItem
    let isToggling: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void

    var appIcon: NSImage {
        let p = item.appPath
        return NSWorkspace.shared.icon(forFile: FileManager.default.fileExists(atPath: p) ? p : item.programPath)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: appIcon).resizable().frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(.body.weight(.medium))
                Text(item.programPath).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text(item.label).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }

            Spacer()

            if item.isSystem {
                Text("Système").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }

            // Toggle with loading state
            if isToggling {
                ProgressView().scaleEffect(0.75).frame(width: 44)
            } else {
                Toggle("", isOn: Binding(
                    get: { item.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(item.isSystem)
            }

            Button(action: onReveal) {
                Image(systemName: "folder").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Afficher dans le Finder")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(item.isEnabled ? Color.green.opacity(0.04) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(item.isEnabled ? Color.green.opacity(0.2) : Color.clear, lineWidth: 1))
        .opacity(item.isSystem ? 0.7 : 1.0)
    }
}
