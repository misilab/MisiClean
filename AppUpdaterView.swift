//
//  AppUpdaterView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct AppUpdate: Identifiable {
    let id = UUID()
    let displayName: String
    let caskName: String
    let installedVersion: String
    let latestVersion: String
    var isUpdating = false
    var isDone = false
    var failed = false
}

// MARK: - ViewModel

@MainActor
class AppUpdaterViewModel: ObservableObject {
    @Published var updates: [AppUpdate] = []
    @Published var isChecking = false
    @Published var hasChecked = false
    @Published var brewAvailable = false
    @Published var isUpdatingAll = false

    var pendingCount: Int { updates.filter { !$0.isDone }.count }

    func check() async {
        isChecking = true; hasChecked = true
        defer { isChecking = false }
        let (available, result) = await Task.detached(priority: .userInitiated) {
            AppUpdaterViewModel.checkBrew()
        }.value
        brewAvailable = available
        withAnimation { updates = result }
    }

    func update(_ item: AppUpdate) async {
        guard let idx = updates.firstIndex(where: { $0.id == item.id }) else { return }
        updates[idx].isUpdating = true
        let cask = item.caskName
        let success = await Task.detached(priority: .userInitiated) {
            AppUpdaterViewModel.runUpgrade(cask: cask)
        }.value
        updates[idx].isUpdating = false
        updates[idx].isDone = success
        updates[idx].failed = !success
    }

    func updateAll() async {
        isUpdatingAll = true
        defer { isUpdatingAll = false }
        for item in updates where !item.isDone {
            await update(item)
        }
    }

    nonisolated static func brewBinary() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    nonisolated static func checkBrew() -> (Bool, [AppUpdate]) {
        guard let brew = brewBinary() else { return (false, []) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: brew)
        proc.arguments = ["outdated", "--cask", "--json=v2"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return (true, []) }
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]] else { return (true, []) }

        let updates: [AppUpdate] = casks.compactMap { cask in
            guard let name      = cask["name"] as? String,
                  let versions  = cask["installed_versions"] as? [String],
                  let current   = cask["current_version"] as? String,
                  let installed = versions.first else { return nil }
            let display = name.split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            return AppUpdate(displayName: display, caskName: name,
                             installedVersion: installed, latestVersion: current)
        }
        return (true, updates)
    }

    nonisolated static func runUpgrade(cask: String) -> Bool {
        guard let brew = brewBinary() else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: brew)
        proc.arguments = ["upgrade", "--cask", cask]
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
}

// MARK: - Section View

struct AppUpdaterSection: View {
    @ObservedObject var vm: AppUpdaterViewModel
    private let accent = Color(red: 0.0, green: 0.55, blue: 0.88)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Group {
                if vm.isChecking {
                    loadingState
                } else if !vm.hasChecked {
                    initialState
                } else if !vm.brewAvailable {
                    noBrewState
                } else if vm.updates.isEmpty {
                    upToDateState
                } else {
                    updateList
                    Divider()
                    footer
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mises à jour").font(.callout.weight(.semibold))
                if vm.hasChecked && !vm.updates.isEmpty {
                    Text("\(vm.pendingCount) mise\(vm.pendingCount != 1 ? "s" : "") à jour disponible\(vm.pendingCount != 1 ? "s" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Applications Homebrew Cask")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if vm.isChecking { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.check() } } label: {
                Label("Vérifier", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered).disabled(vm.isChecking)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var initialState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(accent.opacity(0.7))
            VStack(spacing: 6) {
                Text("Vérifier les mises à jour").font(.title3.bold())
                Text("Détecte les applications Homebrew Cask obsolètes sur votre Mac.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button { Task { await vm.check() } } label: {
                Label("Vérifier maintenant", systemImage: "magnifyingglass")
                    .font(.callout.weight(.semibold)).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .tint(accent).keyboardShortcut("r", modifiers: .command)
            Spacer()
        }
        .padding(32)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().scaleEffect(1.3)
            Text("Vérification des mises à jour…").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var noBrewState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(Color.secondary.opacity(0.4))
            VStack(spacing: 6) {
                Text("Homebrew non installé").font(.title3.bold())
                Text("Cette fonctionnalité nécessite Homebrew pour détecter les mises à jour des applications tierces.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(32)
    }

    private var upToDateState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(Color.green.opacity(0.7))
            VStack(spacing: 6) {
                Text("Tout est à jour").font(.title3.bold())
                Text("Toutes vos applications Homebrew sont à leur dernière version.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(32)
    }

    private var updateList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach($vm.updates) { $update in
                    AppUpdateRow(update: $update, accent: accent) {
                        Task { await vm.update(update) }
                    }
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(vm.pendingCount) en attente")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            if vm.isUpdatingAll {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.75)
                    Text("Mise à jour…").font(.callout).foregroundStyle(.secondary)
                }
            }
            Button { Task { await vm.updateAll() } } label: {
                Label("Tout mettre à jour", systemImage: "arrow.down.app")
            }
            .buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
            .disabled(vm.isUpdatingAll || vm.updates.allSatisfy(\.isDone))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Update Row

struct AppUpdateRow: View {
    @Binding var update: AppUpdate
    let accent: Color
    let onUpdate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accent.opacity(0.1)).frame(width: 36, height: 36)
                Image(systemName: "app.fill")
                    .font(.system(size: 16)).foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(update.displayName).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(update.installedVersion)
                        .font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(update.latestVersion).font(.caption).foregroundStyle(accent)
                }
            }

            Spacer()

            Group {
                if update.isDone {
                    Label("Mis à jour", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                } else if update.failed {
                    Label("Erreur", systemImage: "exclamationmark.circle.fill")
                        .font(.caption).foregroundStyle(.red)
                } else if update.isUpdating {
                    ProgressView().scaleEffect(0.75).frame(width: 90)
                } else {
                    Button("Mettre à jour", action: onUpdate)
                        .buttonStyle(.bordered).tint(accent).controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .opacity(update.isDone ? 0.6 : 1.0)
    }
}
