//
//  PermissionsAuditView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

// MARK: - Model

struct AppPermission: Identifiable {
    let id = UUID()
    let bundleID: String
    let service: String
    let allowed: Bool

    var appName: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }

    var serviceDisplayName: String { Self.serviceNames[service] ?? service.replacingOccurrences(of: "kTCCService", with: "") }
    var serviceIcon: String        { Self.serviceIcons[service] ?? "key.fill" }
    var serviceColor: Color        { Self.serviceColors[service] ?? .teal }

    static let serviceNames: [String: String] = [
        "kTCCServiceCamera":               "Caméra",
        "kTCCServiceMicrophone":           "Micro",
        "kTCCServiceLocation":             "Localisation",
        "kTCCServiceContacts":             "Contacts",
        "kTCCServiceCalendar":             "Calendrier",
        "kTCCServiceReminders":            "Rappels",
        "kTCCServicePhotos":               "Photos",
        "kTCCServiceScreenCapture":        "Capture d'écran",
        "kTCCServiceAccessibility":        "Accessibilité",
        "kTCCServiceSystemPolicyAllFiles": "Accès disque complet",
        "kTCCServiceAddressBook":          "Carnet d'adresses",
        "kTCCServiceAppleEvents":          "Automatisation",
        "kTCCServiceMediaLibrary":         "Médiathèque",
        "kTCCServiceListenEvent":          "Écoute clavier",
        "kTCCServicePostEvent":            "Contrôle système",
        "kTCCServiceDeveloperTool":        "Outils développeur",
    ]
    static let serviceIcons: [String: String] = [
        "kTCCServiceCamera":               "camera.fill",
        "kTCCServiceMicrophone":           "mic.fill",
        "kTCCServiceLocation":             "location.fill",
        "kTCCServiceContacts":             "person.crop.circle.fill",
        "kTCCServiceCalendar":             "calendar",
        "kTCCServiceReminders":            "list.bullet",
        "kTCCServicePhotos":               "photo.fill",
        "kTCCServiceScreenCapture":        "rectangle.dashed",
        "kTCCServiceAccessibility":        "accessibility",
        "kTCCServiceSystemPolicyAllFiles": "lock.open.fill",
        "kTCCServiceAddressBook":          "person.crop.circle.fill",
        "kTCCServiceAppleEvents":          "arrow.2.squarepath",
        "kTCCServiceMediaLibrary":         "music.note",
        "kTCCServiceListenEvent":          "ear.fill",
        "kTCCServicePostEvent":            "desktopcomputer",
        "kTCCServiceDeveloperTool":        "hammer.fill",
    ]
    static let serviceColors: [String: Color] = [
        "kTCCServiceCamera":               Color(red: 0.88, green: 0.15, blue: 0.15),
        "kTCCServiceMicrophone":           .orange,
        "kTCCServiceLocation":             Color(red: 0.0, green: 0.55, blue: 0.9),
        "kTCCServiceScreenCapture":        .purple,
        "kTCCServiceSystemPolicyAllFiles": .blue,
        "kTCCServiceAccessibility":        .indigo,
        "kTCCServiceContacts":             Color(red: 0.2, green: 0.7, blue: 0.4),
        "kTCCServicePhotos":               Color(red: 0.85, green: 0.3, blue: 0.5),
        "kTCCServiceCalendar":             Color(red: 0.9, green: 0.2, blue: 0.2),
        "kTCCServiceReminders":            Color(red: 1.0, green: 0.55, blue: 0.0),
    ]

    static let priorityServices: [String] = [
        "kTCCServiceCamera", "kTCCServiceMicrophone", "kTCCServiceScreenCapture",
        "kTCCServiceSystemPolicyAllFiles", "kTCCServiceAccessibility", "kTCCServiceLocation",
        "kTCCServiceContacts", "kTCCServicePhotos", "kTCCServiceCalendar", "kTCCServiceReminders",
        "kTCCServiceAppleEvents", "kTCCServiceListenEvent", "kTCCServiceDeveloperTool",
    ]
}

// MARK: - ViewModel

@MainActor
class PermissionsAuditViewModel: ObservableObject {
    @Published var permissions: [AppPermission] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var fdaRequired = false
    @Published var selectedService: String? = nil

    var services: [String] {
        let all = Set(permissions.map(\.service))
        let sorted = AppPermission.priorityServices.filter { all.contains($0) }
        let rest = all.subtracting(AppPermission.priorityServices).sorted()
        return sorted + rest
    }

    var filteredPermissions: [AppPermission] {
        let src = selectedService == nil
            ? permissions
            : permissions.filter { $0.service == selectedService }
        return src.sorted { $0.appName.localizedCompare($1.appName) == .orderedAscending }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; hasLoaded = true; fdaRequired = false

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbs = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]

        var result: [AppPermission] = []
        var anyUnreadable = false

        for db in dbs {
            let output = await Task.detached(priority: .userInitiated) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
                proc.arguments = [db, "SELECT client, service, auth_value FROM access WHERE auth_value IN (0, 1, 2);"]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = Pipe()
                try? proc.run(); proc.waitUntilExit()
                return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            }.value

            // If the DB file exists but sqlite3 returned nothing, we likely lack FDA
            if output.isEmpty && FileManager.default.fileExists(atPath: db) { anyUnreadable = true }

            for line in output.split(separator: "\n") {
                let parts = line.split(separator: "|")
                guard parts.count >= 3, let authValue = Int(parts[2]) else { continue }
                let bundleID = String(parts[0]); let service = String(parts[1])
                guard !bundleID.isEmpty, !service.isEmpty else { continue }
                result.append(AppPermission(bundleID: bundleID, service: service, allowed: authValue == 2))
            }
        }

        if anyUnreadable && result.isEmpty { fdaRequired = true }

        // Deduplicate: keep allowed over denied for same pair
        var seen = [String: AppPermission]()
        for p in result {
            let key = p.bundleID + "|" + p.service
            if seen[key] == nil || p.allowed { seen[key] = p }
        }
        permissions = Array(seen.values).filter { $0.allowed }
        isLoading = false
    }

    func revokePermission(_ permission: AppPermission) async {
        await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            proc.arguments = ["reset", permission.service, permission.bundleID]
            proc.standardError = Pipe()
            try? proc.run(); proc.waitUntilExit()
        }.value
        await load()
    }
}

// MARK: - Section View

struct PermissionsAuditSection: View {
    @ObservedObject var vm: PermissionsAuditViewModel
    @State private var revokingID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Group {
                if vm.isLoading {
                    loadingView
                } else if !vm.hasLoaded {
                    initialView
                } else if vm.fdaRequired {
                    fdaRequiredView
                } else {
                    mainContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Audit des permissions").font(.callout.weight(.semibold))
                if vm.hasLoaded && !vm.isLoading && !vm.fdaRequired {
                    Text("\(vm.permissions.count) autorisations · \(vm.services.count) services")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Quelles apps ont accès à quoi sur votre Mac")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if vm.isLoading { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.load() } } label: {
                Label("Analyser", systemImage: "lock.shield")
            }
            .buttonStyle(.bordered)
            .disabled(vm.isLoading)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: States

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView("Lecture des bases TCC…").scaleEffect(1.1)
            Spacer()
        }
    }

    private var initialView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(Color.indigo.opacity(0.10)).frame(width: 90, height: 90)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40, weight: .thin)).foregroundStyle(Color.indigo)
            }
            VStack(spacing: 8) {
                Text("Audit des permissions").font(.title3.bold())
                Text("Voyez quelles applications ont accès à votre caméra, micro,\ncontacts, localisation et bien plus — et révoquez en un clic.")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            Button { Task { await vm.load() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                    Text("Analyser les permissions")
                }
                .font(.title3.weight(.semibold)).foregroundStyle(.white)
                .frame(minWidth: 260).padding(.vertical, 14)
                .background(Color.indigo, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.indigo.opacity(0.4), radius: 14, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(40)
    }

    private var fdaRequiredView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .font(.system(size: 48)).foregroundStyle(.orange)
            VStack(spacing: 8) {
                Text("Accès complet au disque requis").font(.title3.bold())
                Text("Pour lire les bases TCC, accordez l'accès complet au disque à MisiClean dans les Réglages Système → Confidentialité.")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 400)
            }
            Button("Ouvrir les Réglages") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(40)
    }

    // MARK: Main content (service sidebar + list)

    private var mainContent: some View {
        HStack(spacing: 0) {
            serviceFilterSidebar
            Divider()
            permissionList
        }
    }

    private var serviceFilterSidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Service")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)

                PermServiceRow(
                    label: "Tout", icon: "list.bullet", color: .secondary,
                    count: vm.permissions.count, isSelected: vm.selectedService == nil
                ) { vm.selectedService = nil }

                ForEach(vm.services, id: \.self) { svc in
                    let sample = AppPermission(bundleID: "", service: svc, allowed: true)
                    let count = vm.permissions.filter { $0.service == svc }.count
                    PermServiceRow(
                        label: sample.serviceDisplayName,
                        icon: sample.serviceIcon,
                        color: sample.serviceColor,
                        count: count,
                        isSelected: vm.selectedService == svc
                    ) { vm.selectedService = svc }
                }
            }
            .padding(.bottom, 8)
        }
        .frame(width: 190)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var permissionList: some View {
        let filtered = vm.filteredPermissions
        return ScrollView {
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 60)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 40)).foregroundStyle(.green.opacity(0.6))
                    Text("Aucune app autorisée pour ce service").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(filtered) { perm in
                        PermissionRowView(perm: perm, isRevoking: revokingID == perm.id) {
                            revokingID = perm.id
                            Task {
                                await vm.revokePermission(perm)
                                revokingID = nil
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Service filter row

private struct PermServiceRow: View {
    let label: String; let icon: String; let color: Color
    let count: Int; let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.08))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon)
                        .font(.system(size: 11)).foregroundStyle(isSelected ? color : Color.secondary)
                }
                Text(label)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : Color.secondary)
                Spacer()
                Text("\(count)").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected
                          ? color.opacity(0.12)
                          : hovering ? Color.secondary.opacity(0.06) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 8)
        .onHover { hovering = $0 }
    }
}

// MARK: - Permission row

private struct PermissionRowView: View {
    let perm: AppPermission
    let isRevoking: Bool
    let onRevoke: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(perm.serviceColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: perm.serviceIcon)
                    .font(.system(size: 17)).foregroundStyle(perm.serviceColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(perm.appName).font(.body.weight(.medium)).lineLimit(1)
                Text(perm.bundleID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            Text(perm.serviceDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(perm.serviceColor)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(perm.serviceColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))

            if isRevoking {
                ProgressView().scaleEffect(0.7).frame(width: 70)
            } else {
                Button("Révoquer", action: onRevoke)
                    .buttonStyle(.bordered).tint(.red).controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(perm.serviceColor.opacity(0.15), lineWidth: 1))
        .opacity(isRevoking ? 0.6 : 1)
    }
}
