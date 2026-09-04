//
//  ContentView.swift
//  MisiClean
//

import SwiftUI
import AppKit

// MARK: - App Sections

enum AppSection: CaseIterable, Identifiable, Hashable {
    case clean, largeFiles, oldFiles, duplicates, devTools, archives, orphanPrefs, scheduledCleaning
    case uninstaller, iOSBackups, loginItems, browserExt, appUpdater, dormantApps
    case privacy, memory, maintenance, snapshots, launchAgents, appPermissions, battery, diskHealth, malwareScanner, networkMonitor
    case diskMap, diskExplorer, metadataCleaner, keychainAudit, sysInfo, history
    case xcodeCleaner, topProcesses
    case mailAttachments, crashReports, sandboxOrphans, sleepImage
    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .clean:        return "Nettoyage"
        case .largeFiles:   return "Gros fichiers"
        case .oldFiles:     return "Vieux fichiers"
        case .duplicates:   return "Doublons"
        case .devTools:     return "Outils Dev"
        case .uninstaller:  return "Désinstaller"
        case .iOSBackups:   return "Sauvegardes iOS"
        case .loginItems:   return "Démarrage"
        case .browserExt:   return "Extensions"
        case .privacy:      return "Confidentialité"
        case .memory:       return "Mémoire"
        case .maintenance:  return "Maintenance"
        case .snapshots:    return "Snapshots APFS"
        case .launchAgents: return "Agents"
        case .diskMap:      return "Carte disque"
        case .diskExplorer: return "Explorateur"
        case .sysInfo:      return "Mon Mac"
        case .history:          return "Historique"
        case .appUpdater:       return "Mises à jour"
        case .scheduledCleaning:return "Planification"
        case .archives:         return "Archives"
        case .orphanPrefs:      return "Préf. orphelines"
        case .dormantApps:      return "Apps dormantes"
        case .appPermissions:   return "Permissions"
        case .battery:          return "Batterie"
        case .diskHealth:       return "Santé disque"
        case .malwareScanner:   return "Antivirus"
        case .networkMonitor:   return "Réseau"
        case .metadataCleaner:  return "Métadonnées"
        case .keychainAudit:    return "Trousseau"
        case .xcodeCleaner:     return "Xcode"
        case .topProcesses:     return "Processus"
        case .mailAttachments:  return "Pièces jointes"
        case .crashReports:     return "Crash reports"
        case .sandboxOrphans:   return "Sandbox"
        case .sleepImage:       return "Mémoire virt."
        }
    }

    var icon: String {
        switch self {
        case .clean:        return "sparkles"
        case .largeFiles:   return "doc.fill.badge.ellipsis"
        case .oldFiles:     return "calendar.badge.clock"
        case .duplicates:   return "doc.on.doc.fill"
        case .devTools:     return "hammer.circle.fill"
        case .uninstaller:  return "trash.circle.fill"
        case .iOSBackups:   return "iphone"
        case .loginItems:   return "bolt.fill"
        case .browserExt:   return "puzzlepiece.fill"
        case .privacy:      return "eye.slash.fill"
        case .memory:       return "memorychip"
        case .maintenance:  return "wrench.and.screwdriver.fill"
        case .snapshots:    return "camera.fill"
        case .launchAgents: return "bolt.horizontal.circle.fill"
        case .diskMap:      return "square.grid.2x2.fill"
        case .diskExplorer: return "internaldrive"
        case .sysInfo:      return "desktopcomputer"
        case .history:          return "clock.arrow.circlepath"
        case .appUpdater:       return "arrow.down.app.fill"
        case .scheduledCleaning:return "timer"
        case .archives:         return "archivebox.fill"
        case .orphanPrefs:      return "doc.badge.gearshape.fill"
        case .dormantApps:      return "clock.badge.questionmark"
        case .appPermissions:   return "lock.shield.fill"
        case .battery:          return "battery.100.bolt"
        case .diskHealth:       return "externaldrive.badge.checkmark"
        case .malwareScanner:   return "shield.lefthalf.filled.trianglebadge.exclamationmark"
        case .networkMonitor:   return "network"
        case .metadataCleaner:  return "location.slash.fill"
        case .keychainAudit:    return "key.fill"
        case .xcodeCleaner:     return "hammer.fill"
        case .topProcesses:     return "cpu"
        case .mailAttachments:  return "paperclip"
        case .crashReports:     return "ladybug.fill"
        case .sandboxOrphans:   return "shippingbox.fill"
        case .sleepImage:       return "moon.fill"
        }
    }

    var accent: Color {
        switch self {
        case .clean:        return .blue
        case .largeFiles:   return .orange
        case .oldFiles:     return Color(red: 0.85, green: 0.45, blue: 0.05)
        case .duplicates:   return Color(red: 0.95, green: 0.55, blue: 0.1)
        case .devTools:     return .mint
        case .uninstaller:  return .red
        case .iOSBackups:   return Color(red: 0.3, green: 0.5, blue: 0.9)
        case .loginItems:   return Color(red: 0.85, green: 0.65, blue: 0.0)
        case .browserExt:   return Color(red: 0.1, green: 0.6, blue: 0.3)
        case .privacy:      return .indigo
        case .memory:       return .green
        case .maintenance:  return Color(red: 0.35, green: 0.6, blue: 0.85)
        case .snapshots:    return Color(red: 0.6, green: 0.25, blue: 0.9)
        case .launchAgents: return Color(red: 0.75, green: 0.38, blue: 0.1)
        case .diskMap:      return Color(red: 0.1, green: 0.68, blue: 0.45)
        case .diskExplorer: return Color(red: 0.2, green: 0.5, blue: 0.9)
        case .sysInfo:      return .cyan
        case .history:          return .teal
        case .appUpdater:       return Color(red: 0.0,  green: 0.55, blue: 0.88)
        case .scheduledCleaning:return Color(red: 0.5,  green: 0.28, blue: 0.92)
        case .archives:         return Color(red: 0.60, green: 0.45, blue: 0.20)
        case .orphanPrefs:      return Color(red: 0.55, green: 0.28, blue: 0.92)
        case .dormantApps:      return Color(red: 0.50, green: 0.28, blue: 0.92)
        case .appPermissions:   return .indigo
        case .battery:          return Color(red: 0.15, green: 0.75, blue: 0.35)
        case .diskHealth:       return Color(red: 0.10, green: 0.68, blue: 0.45)
        case .malwareScanner:   return Color(red: 0.88, green: 0.15, blue: 0.15)
        case .networkMonitor:   return Color(red: 0.00, green: 0.55, blue: 0.90)
        case .metadataCleaner:  return Color(red: 0.88, green: 0.30, blue: 0.50)
        case .keychainAudit:    return Color(red: 0.35, green: 0.55, blue: 0.95)
        case .xcodeCleaner:     return Color(red: 0.95, green: 0.55, blue: 0.1)
        case .topProcesses:     return Color(red: 0.35, green: 0.6, blue: 0.85)
        case .mailAttachments:  return Color(red: 0.1,  green: 0.55, blue: 0.9)
        case .crashReports:     return Color(red: 0.88, green: 0.35, blue: 0.15)
        case .sandboxOrphans:   return Color(red: 0.5,  green: 0.35, blue: 0.85)
        case .sleepImage:       return Color(red: 0.3,  green: 0.45, blue: 0.85)
        }
    }
}

private let leftSidebarGroups: [(String, [AppSection])] = [
    ("Nettoyage",    [.clean, .largeFiles, .oldFiles, .duplicates, .archives, .orphanPrefs, .devTools, .xcodeCleaner, .scheduledCleaning, .mailAttachments, .crashReports]),
    ("Applications", [.uninstaller, .iOSBackups, .loginItems, .browserExt, .appUpdater, .dormantApps, .sandboxOrphans]),
]

private let rightSidebarGroups: [(String, [AppSection])] = [
    ("Système",      [.privacy, .memory, .topProcesses, .maintenance, .snapshots, .launchAgents, .appPermissions, .battery, .diskHealth, .malwareScanner, .networkMonitor, .sleepImage]),
    ("Outils",       [.diskMap, .diskExplorer, .metadataCleaner, .keychainAudit, .sysInfo, .history]),
]

// MARK: - Root

struct ContentView: View {
    @State private var section: AppSection = .clean
    @StateObject private var cleanerVM      = CleanerViewModel()
    @StateObject private var largeFilesVM   = LargeFilesViewModel()
    @StateObject private var duplicatesVM   = DuplicatesViewModel()
    @StateObject private var uninstallerVM  = AppUninstallerViewModel()
    @StateObject private var loginItemsVM   = LoginItemsViewModel()
    @StateObject private var privacyVM      = PrivacyViewModel()
    @StateObject private var memoryVM       = MemoryViewModel()
    @StateObject private var maintenanceVM   = MaintenanceViewModel()
    @StateObject private var diskExplorerVM  = DiskExplorerViewModel()
    @StateObject private var oldFilesVM      = OldFilesViewModel()
    @StateObject private var devToolsVM      = DevToolsViewModel()
    @StateObject private var snapshotsVM     = SnapshotsViewModel()
    @StateObject private var browserExtVM    = BrowserExtensionsViewModel()
    @StateObject private var sysInfoVM       = SystemInfoViewModel()
    @StateObject private var iOSBackupsVM    = IOSBackupsViewModel()
    @StateObject private var launchAgentsVM  = LaunchAgentsViewModel()
    @StateObject private var diskMapVM        = DiskMapViewModel()
    @StateObject private var appUpdaterVM    = AppUpdaterViewModel()
    @StateObject private var scheduledVM     = ScheduledCleaningViewModel()
    @StateObject private var batteryVM       = BatteryViewModel()
    @StateObject private var malwareScannerVM = MalwareScannerViewModel()
    @StateObject private var permissionsVM    = PermissionsAuditViewModel()
    @StateObject private var diskHealthVM     = DiskHealthViewModel()
    @StateObject private var dormantAppsVM    = DormantAppsViewModel()
    @StateObject private var archivesVM       = ArchivesViewModel()
    @StateObject private var orphanPrefsVM    = OrphanPrefsViewModel()
    @StateObject private var networkMonitorVM = NetworkMonitorViewModel()
    @StateObject private var metadataVM       = MetadataCleanerViewModel()
    @StateObject private var keychainVM         = KeychainAuditViewModel()
    @StateObject private var mailAttachmentsVM  = MailAttachmentsViewModel()
    @StateObject private var crashReportsVM     = CrashReportsViewModel()
    @StateObject private var sandboxOrphansVM   = SandboxOrphansViewModel()
    @StateObject private var sleepImageVM       = SleepImageViewModel()
    @ObservedObject private var updateManager = SelfUpdateManager.shared
    @State private var hasFDA: Bool = ContentView.checkFDA()
    @State private var diskInfo: DiskInfo = .load()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainContent
            Divider()
            rightSidebar
        }
        .frame(width: 1260, height: 860)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            withAnimation { hasFDA = ContentView.checkFDA() }
            diskInfo = .load()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            appHeader
            Divider()
            sidebarNav
            Spacer(minLength: 0)
            Divider()
            miniDiskGauge
        }
        .frame(width: 196)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [Color(red: 0.15, green: 0.38, blue: 0.95).opacity(0.06), .clear],
                    startPoint: .top, endPoint: .center
                )
            }
        }
    }

    private var appHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
                .shadow(color: Color(red: 0.3, green: 0.2, blue: 0.9).opacity(0.3), radius: 6, x: 0, y: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text("MisiClean").font(.callout.weight(.bold))
                Text("Nettoyeur Mac").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var sidebarNav: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(leftSidebarGroups, id: \.0) { (group, sections) in
                    Text(LocalizedStringKey(group))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                    ForEach(sections) { s in
                        SidebarItem(section: s, isSelected: section == s) {
                            withAnimation(.easeInOut(duration: 0.18)) { section = s }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: Right Sidebar

    private var rightSidebar: some View {
        VStack(spacing: 0) {
            rightSidebarNav
            Spacer(minLength: 0)
        }
        .frame(width: 184)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.15, blue: 0.90).opacity(0.05), .clear],
                    startPoint: .top, endPoint: .center
                )
            }
        }
    }

    private var rightSidebarNav: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rightSidebarGroups, id: \.0) { (group, sections) in
                    Text(LocalizedStringKey(group))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                    ForEach(sections) { s in
                        SidebarItem(section: s, isSelected: section == s) {
                            withAnimation(.easeInOut(duration: 0.18)) { section = s }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var miniDiskGauge: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 3)
                    .frame(width: 26, height: 26)
                Circle()
                    .trim(from: 0, to: min(diskInfo.usedFraction, 1))
                    .stroke(
                        diskInfo.usedFraction > 0.9
                            ? LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : diskInfo.usedFraction > 0.75
                                ? LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color(red: 0.15, green: 0.38, blue: 0.95), Color(red: 0.55, green: 0.15, blue: 0.90)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(-90))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(diskInfo.availableBytes.formattedSize) libres")
                    .font(.caption.weight(.medium))
                Text("\(Int(diskInfo.usedFraction * 100))% utilisé")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            if !hasFDA {
                FDABanner { withAnimation { hasFDA = ContentView.checkFDA() } }
            }
            if let update = updateManager.availableUpdate {
                UpdateBanner(
                    update: update,
                    manager: updateManager,
                    onDismiss: { updateManager.dismissUpdate() }
                )
            }
            ZStack {
                switch section {
                case .clean:
                    NettoyageSection(vm: cleanerVM).transition(.opacity)
                case .largeFiles:
                    LargeFilesSection(vm: largeFilesVM).transition(.opacity)
                case .oldFiles:
                    OldFilesSection(vm: oldFilesVM).transition(.opacity)
                case .devTools:
                    DevToolsSection(vm: devToolsVM).transition(.opacity)
                case .duplicates:
                    DuplicatesSection(vm: duplicatesVM).transition(.opacity)
                case .uninstaller:
                    AppUninstallerSection(vm: uninstallerVM).transition(.opacity)
                case .iOSBackups:
                    IOSBackupsSection(vm: iOSBackupsVM).transition(.opacity)
                case .loginItems:
                    LoginItemsSection(vm: loginItemsVM).transition(.opacity)
                case .browserExt:
                    BrowserExtensionsSection(vm: browserExtVM).transition(.opacity)
                case .privacy:
                    PrivacySection(vm: privacyVM).transition(.opacity)
                case .memory:
                    MemorySection(vm: memoryVM).transition(.opacity)
                case .maintenance:
                    MaintenanceSection(vm: maintenanceVM).transition(.opacity)
                case .snapshots:
                    SnapshotsSection(vm: snapshotsVM).transition(.opacity)
                case .launchAgents:
                    LaunchAgentsSection(vm: launchAgentsVM).transition(.opacity)
                case .diskMap:
                    DiskMapSection(vm: diskMapVM).transition(.opacity)
                case .diskExplorer:
                    DiskExplorerSection(vm: diskExplorerVM).transition(.opacity)
                case .sysInfo:
                    SystemInfoSection(vm: sysInfoVM).transition(.opacity)
                case .history:
                    HistorySection().transition(.opacity)
                case .appUpdater:
                    AppUpdaterSection(vm: appUpdaterVM).transition(.opacity)
                case .scheduledCleaning:
                    ScheduledCleaningSection(vm: scheduledVM).transition(.opacity)
                case .battery:
                    BatterySection(vm: batteryVM).transition(.opacity)
                case .archives:
                    ArchivesSection(vm: archivesVM).transition(.opacity)
                case .dormantApps:
                    DormantAppsSection(vm: dormantAppsVM).transition(.opacity)
                case .appPermissions:
                    PermissionsAuditSection(vm: permissionsVM).transition(.opacity)
                case .diskHealth:
                    DiskHealthSection(vm: diskHealthVM).transition(.opacity)
                case .malwareScanner:
                    MalwareScannerSection(vm: malwareScannerVM).transition(.opacity)
                case .orphanPrefs:
                    OrphanPrefsSection(vm: orphanPrefsVM).transition(.opacity)
                case .networkMonitor:
                    NetworkMonitorSection(vm: networkMonitorVM).transition(.opacity)
                case .metadataCleaner:
                    MetadataCleanerSection(vm: metadataVM).transition(.opacity)
                case .keychainAudit:
                    KeychainAuditSection(vm: keychainVM).transition(.opacity)
                case .xcodeCleaner:
                    XcodeCleanerSection().transition(.opacity)
                case .topProcesses:
                    TopProcessesSection().transition(.opacity)
                case .mailAttachments:
                    MailAttachmentsSection(vm: mailAttachmentsVM).transition(.opacity)
                case .crashReports:
                    CrashReportsSection(vm: crashReportsVM).transition(.opacity)
                case .sandboxOrphans:
                    SandboxOrphansSection(vm: sandboxOrphansVM).transition(.opacity)
                case .sleepImage:
                    SleepImageSection(vm: sleepImageVM).transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    nonisolated static func checkFDA() -> Bool {
        let fm = FileManager.default
        // Try to enumerate an FDA-protected directory — metadata checks aren't reliable on macOS 15
        let safariLib = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari").path
        if (try? fm.contentsOfDirectory(atPath: safariLib)) != nil { return true }
        return (try? fm.contentsOfDirectory(atPath: "/Library/Application Support/com.apple.TCC")) != nil
    }
}

// MARK: - Sidebar Item

struct SidebarItem: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(
                            colors: isSelected
                                ? [section.accent, section.accent.opacity(0.7)]
                                : [Color.secondary.opacity(0.1), Color.secondary.opacity(0.07)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 26, height: 26)
                        .shadow(color: isSelected ? section.accent.opacity(0.4) : .clear,
                                radius: 4, x: 0, y: 2)
                    Image(systemName: section.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? .white : Color.secondary)
                }
                Text(section.label)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : Color.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected
                              ? LinearGradient(
                                    colors: [section.accent.opacity(0.18), section.accent.opacity(0.05)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                              : LinearGradient(
                                    colors: [isHovering ? Color.secondary.opacity(0.07) : .clear, .clear],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                    if isSelected {
                        Capsule()
                            .fill(section.accent)
                            .frame(width: 3)
                            .padding(.vertical, 5)
                            .shadow(color: section.accent.opacity(0.6), radius: 4, x: 0, y: 0)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { isHovering = $0 }
    }
}

// MARK: - FDA Banner

struct FDABanner: View {
    let onRecheck: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text("Accès complet au disque requis")
                    .font(.callout.weight(.semibold))
                Text("Sans cet accès, macOS affiche une boîte de dialogue pour chaque dossier protégé.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button("Ouvrir les Réglages") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                )
            }
            .buttonStyle(.bordered)

            Button(action: onRecheck) {
                Image(systemName: "arrow.clockwise").font(.callout)
            }
            .buttonStyle(.plain)
            .help("Vérifier à nouveau")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Update Banner

struct UpdateBanner: View {
    let update: UpdateInfo
    @ObservedObject var manager: SelfUpdateManager
    let onDismiss: () -> Void

    private var isActive: Bool {
        if case .idle = manager.installState { return false }
        if case .cancelled = manager.installState { return false }
        if case .failed = manager.installState { return false }
        return true
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .symbolEffect(.pulse, isActive: isActive)

            VStack(alignment: .leading, spacing: 3) {
                Text("MisiClean \(update.version) disponible")
                    .font(.callout.weight(.semibold))

                switch manager.installState {
                case .downloading(let p):
                    ProgressView(value: p)
                        .frame(maxWidth: 220)
                        .tint(.green)
                    Text("Téléchargement \(Int(p * 100)) %…")
                        .font(.caption).foregroundStyle(.secondary)

                case .installing:
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(height: 12)
                    Text("Installation en cours…")
                        .font(.caption).foregroundStyle(.secondary)

                case .done:
                    Text("Installé — redémarrage…")
                        .font(.caption).foregroundStyle(.green)

                case .failed(let msg):
                    Text(msg)
                        .font(.caption).foregroundStyle(.red)

                case .cancelled:
                    Text("Installation annulée")
                        .font(.caption).foregroundStyle(.secondary)

                case .idle:
                    if let date = update.publishedAt {
                        Text("Publié le \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Prête à être installée automatiquement")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if !isActive {
                Button("Installer") {
                    Task { await manager.downloadAndInstall() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Ignorer cette mise à jour")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Nettoyage Section

struct NettoyageSection: View {
    @ObservedObject var vm: CleanerViewModel

    var body: some View {
        ZStack {
            if !vm.hasResults && !vm.isScanning {
                WelcomeView(vm: vm)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                NettoyageMainView(vm: vm)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.hasResults || vm.isScanning)
        .sheet(isPresented: $vm.showConfirmation) { ConfirmationSheet(vm: vm) }
        .sheet(isPresented: $vm.showResult) { ResultSheet(vm: vm) }
    }
}

// MARK: - Welcome Screen

struct WelcomeView: View {
    @ObservedObject var vm: CleanerViewModel
    @ObservedObject private var monitor = SystemMonitor.shared
    @State private var appeared = false
    @State private var strokeProgress: Double = 0

    private let g1 = Color(red: 0.15, green: 0.38, blue: 0.95)
    private let g2 = Color(red: 0.55, green: 0.15, blue: 0.90)

    private var healthScore: Int {
        var score = 100
        score -= Int(vm.diskInfo.usedFraction * 30)
        score -= Int(Double(monitor.ramPercent) / 100.0 * 20)
        score -= monitor.cpuPercent > 80 ? 10 : monitor.cpuPercent > 50 ? 5 : 0
        if SelfUpdateManager.shared.availableUpdate != nil { score -= 15 }
        if let last = HistoryManager.shared.events.first {
            let days = Calendar.current.dateComponents([.day], from: last.date, to: Date()).day ?? 0
            if days > 30 { score -= 10 } else if days > 7 { score -= 5 }
        } else {
            score -= 10
        }
        return max(0, min(100, score))
    }

    private var ringColor: LinearGradient {
        if healthScore < 50 {
            return LinearGradient(colors: [.red, Color(red: 0.9, green: 0.2, blue: 0.2)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if healthScore < 70 {
            return LinearGradient(colors: [.orange, Color(red: 0.95, green: 0.6, blue: 0.0)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [g1, g2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var ringShadowColor: Color {
        if healthScore < 50 { return Color.red.opacity(0.45) }
        if healthScore < 70 { return Color.orange.opacity(0.45) }
        return g2.opacity(0.5)
    }

    private var healthBadge: some View {
        let (label, color, icon) = healthStatus
        return Label(label, systemImage: icon)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(color, in: Capsule())
            .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 3)
    }

    private var healthStatus: (LocalizedStringKey, Color, String) {
        if healthScore >= 85 { return ("Excellent", Color(red: 0.15, green: 0.68, blue: 0.3), "checkmark.circle.fill") }
        if healthScore >= 70 { return ("Bonne santé", .green, "checkmark.circle.fill") }
        if healthScore >= 50 { return ("À améliorer", .orange, "exclamationmark.circle.fill") }
        return ("Attention requise", .red, "exclamationmark.triangle.fill")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {

                // Hero ring gauge
                ZStack {
                    // Track
                    Circle()
                        .stroke(Color.secondary.opacity(0.08), lineWidth: 16)
                    // Progress stroke
                    Circle()
                        .trim(from: 0, to: strokeProgress)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: ringShadowColor, radius: 10, x: 0, y: 0)
                    // Center content
                    VStack(spacing: 0) {
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("\(healthScore)")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundStyle(LinearGradient(colors: [g1, g2],
                                                               startPoint: .top, endPoint: .bottom))
                            Text("/ 100")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text("santé globale")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 180, height: 180)
                .scaleEffect(appeared ? 1 : 0.75)
                .opacity(appeared ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.65).delay(0.15)) {
                        strokeProgress = Double(healthScore) / 100.0
                    }
                }
                .onChange(of: healthScore) { newScore in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        strokeProgress = Double(newScore) / 100.0
                    }
                }

                // Disk stats
                VStack(spacing: 4) {
                    Text("\(vm.diskInfo.availableBytes.formattedSize) disponibles")
                        .font(.title3.weight(.semibold))
                    Text("sur \(vm.diskInfo.totalBytes.formattedSize) · \(vm.diskInfo.usedBytes.formattedSize) utilisés")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)

                healthBadge.opacity(appeared ? 1 : 0)

                // Health factors row
                HStack(spacing: 8) {
                    HealthFactorCard(icon: "internaldrive", label: "Disque",
                                     value: "\(Int((1 - vm.diskInfo.usedFraction) * 100))%",
                                     ok: vm.diskInfo.usedFraction < 0.75)
                    HealthFactorCard(icon: "memorychip", label: "RAM",
                                     value: "\(100 - monitor.ramPercent)%",
                                     ok: monitor.ramPercent < 75)
                    HealthFactorCard(icon: "cpu", label: "CPU",
                                     value: "\(monitor.cpuPercent)%",
                                     ok: monitor.cpuPercent < 50)
                    HealthFactorCard(icon: "arrow.up.circle", label: "Màj",
                                     value: SelfUpdateManager.shared.availableUpdate == nil ? "OK" : "!",
                                     ok: SelfUpdateManager.shared.availableUpdate == nil)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

                // CTA button
                Button { Task { await vm.scan() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Analyser le disque")
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 240)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [g1, g2], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .shadow(color: g2.opacity(0.5), radius: 16, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 8)

                // Quick Clean
                Button { Task { await vm.quickClean() } } label: {
                    HStack(spacing: 7) {
                        if vm.isQuickCleaning {
                            ProgressView().scaleEffect(0.75)
                            Text("Nettoyage rapide…")
                        } else {
                            Image(systemName: "bolt.fill")
                            Text("Nettoyage rapide")
                        }
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 240)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(vm.isScanning || vm.isQuickCleaning || vm.isCleaning)
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 8)
            }
            Spacer()
        }
        .padding(48).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.05)) { appeared = true }
        }
        .onDisappear {
            appeared = false
            strokeProgress = 0
        }
    }
}

private struct HealthFactorCard: View {
    let icon: String
    let label: String
    let value: String
    let ok: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ok ? Color(red: 0.15, green: 0.68, blue: 0.3) : .orange)
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(width: 58)
        .padding(.vertical, 8)
        .background(
            ok ? Color.green.opacity(0.07) : Color.orange.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ok ? Color.green.opacity(0.2) : Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Nettoyage Main View

struct NettoyageMainView: View {
    @ObservedObject var vm: CleanerViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    ForEach($vm.categories) { $cat in
                        CategoryRowView(category: $cat, maxSize: vm.maxCategorySize)
                    }
                }
                .padding(12)
            }
            Divider()
            footerBar
        }
    }

    private var headerBar: some View {
        HStack(spacing: 16) {
            DiskGaugeView(info: vm.diskInfo)
            Spacer()
            if let date = vm.lastScanDate {
                Text("Analysé à \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Button {
                Task { await vm.scan() }
            } label: {
                Label(vm.isScanning ? "Analyse…" : "Ré-analyser", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(vm.isScanning || vm.isCleaning)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            if vm.hasResults {
                Menu {
                    Button("Tout sélectionner") { vm.setSelectAll(true) }
                    Button("Tout désélectionner") { vm.setSelectAll(false) }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Spacer()
            if vm.isCleaning {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.75)
                    Text("Nettoyage en cours…").font(.callout).foregroundStyle(.secondary)
                }
            } else if vm.totalSelectedBytes > 0 {
                Text("\(vm.totalSelectedBytes.formattedSize) sélectionnés")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Button { vm.requestClean() } label: {
                Label("Nettoyer", systemImage: "trash")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.88, green: 0.15, blue: 0.15),
                                     Color(red: 0.7, green: 0.08, blue: 0.28)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .shadow(color: Color.red.opacity(0.4), radius: 8, x: 0, y: 3)
                    .opacity(vm.totalSelectedBytes == 0 || vm.isCleaning || vm.isScanning ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(vm.totalSelectedBytes == 0 || vm.isCleaning || vm.isScanning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Category Row

struct CategoryRowView: View {
    @Binding var category: CleanCategory
    let maxSize: Int64

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(
                        colors: category.isSelected
                            ? [category.accent.opacity(0.32), category.accent.opacity(0.14)]
                            : [category.accent.opacity(0.16), category.accent.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                Group {
                    if category.isSelected {
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                    } else {
                        Image(systemName: category.icon).font(.system(size: 18))
                    }
                }
                .foregroundStyle(category.accent)
                .transition(.scale.combined(with: .opacity))
            }
            .animation(.spring(response: 0.3), value: category.isSelected)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(category.name))
                    .font(.body.weight(.medium))
                    .foregroundStyle(category.sizeBytes > 0 ? .primary : .secondary)
                Text(LocalizedStringKey(category.description))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if maxSize > 0 && category.sizeBytes > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.1))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [category.accent, category.accent.opacity(0.5)],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: max(3, geo.size.width * CGFloat(category.sizeBytes) / CGFloat(maxSize)))
                        }
                    }
                    .frame(height: 3)
                    .padding(.top, 2)
                    .transition(.opacity)
                }
            }

            Spacer()

            Group {
                if category.isScanning {
                    ProgressView().scaleEffect(0.7).frame(width: 80)
                } else if category.sizeBytes > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(category.sizeBytes.formattedSize)
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(sizeColor)
                        if category.fileCount > 0 {
                            Text("\(category.fileCount) fichier\(category.fileCount > 1 ? "s" : "")")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(minWidth: 80, alignment: .trailing)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    Text("—").foregroundStyle(.tertiary).frame(minWidth: 80, alignment: .trailing)
                }
            }
            .animation(.easeOut(duration: 0.25), value: category.isScanning)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(category.isSelected ? category.accent.opacity(0.07) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(category.isSelected ? category.accent.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard category.sizeBytes > 0 else { return }
            withAnimation(.spring(response: 0.3)) { category.isSelected.toggle() }
        }
    }

    private var sizeColor: Color {
        if category.sizeBytes > 1_000_000_000 { return .red }
        if category.sizeBytes > 200_000_000   { return .orange }
        return .primary
    }
}

// MARK: - Disk Gauge

struct DiskGaugeView: View {
    let info: DiskInfo

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 5)
                    .frame(width: 38, height: 38)
                Circle()
                    .trim(from: 0, to: min(info.usedFraction, 1))
                    .stroke(gaugeGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(info.usedFraction * 100))%")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(info.usedBytes.formattedSize) utilisés")
                    .font(.callout.weight(.medium))
                Text("\(info.availableBytes.formattedSize) disponibles · \(info.totalBytes.formattedSize) total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gaugeGradient: LinearGradient {
        if info.usedFraction > 0.9 {
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if info.usedFraction > 0.75 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(
            colors: [Color(red: 0.15, green: 0.38, blue: 0.95), Color(red: 0.55, green: 0.15, blue: 0.90)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - Confirmation Sheet

struct ConfirmationSheet: View {
    @ObservedObject var vm: CleanerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Confirmer le nettoyage").font(.title3.bold())
                Spacer()
                Button {
                    vm.showConfirmation = false
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Cette action est irréversible. Les fichiers seront supprimés définitivement.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20).padding(.top, 16)

            ScrollView {
                VStack(spacing: 5) {
                    ForEach(vm.selectedCategories) { cat in
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6).fill(cat.accent.opacity(0.12)).frame(width: 28, height: 28)
                                Image(systemName: cat.icon).font(.caption.weight(.semibold)).foregroundStyle(cat.accent)
                            }
                            Text(LocalizedStringKey(cat.name)).font(.callout)
                            Spacer()
                            Text(cat.sizeBytes.formattedSize).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .frame(maxHeight: 220)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Espace à libérer").font(.caption).foregroundStyle(.secondary)
                    Text(vm.totalSelectedBytes.formattedSize).font(.title2.bold().monospacedDigit()).foregroundStyle(.red)
                }
                Spacer()
                Button("Annuler") { vm.showConfirmation = false }.buttonStyle(.bordered).keyboardShortcut(.escape)
                Button {
                    vm.showConfirmation = false
                    Task { await vm.clean() }
                } label: {
                    Label("Supprimer", systemImage: "trash.fill")
                }
                .buttonStyle(.borderedProminent).tint(.red).keyboardShortcut(.return)
            }
            .padding(20)
        }
        .frame(width: 440)
    }
}

// MARK: - Result Sheet

struct ResultSheet: View {
    @ObservedObject var vm: CleanerViewModel
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.12)).frame(width: 90, height: 90)
                    Circle().stroke(Color.green.opacity(0.25), lineWidth: 2).frame(width: 90, height: 90)
                    Image(systemName: "checkmark").font(.system(size: 38, weight: .bold)).foregroundStyle(.green)
                }
                .scaleEffect(appeared ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)

                VStack(spacing: 6) {
                    Text(vm.lastCleanedBytes.formattedSize)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.blue, .green], startPoint: .leading, endPoint: .trailing))
                    Text("libérés sur votre disque").font(.title3).foregroundStyle(.secondary)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

                DiskGaugeView(info: vm.diskInfo).opacity(appeared ? 1 : 0)

                if vm.hasErrors {
                    Label("Certains fichiers protégés n'ont pas pu être supprimés.", systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.caption).foregroundStyle(.orange).opacity(appeared ? 1 : 0)
                }
            }
            Spacer()
            Button("Fermer") { vm.showResult = false }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, 40)
        }
        .frame(width: 360, height: 400)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68).delay(0.08)) { appeared = true }
        }
    }
}

#Preview {
    ContentView()
}
