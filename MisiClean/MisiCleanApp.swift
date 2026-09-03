//
//  MisiCleanApp.swift
//  MisiClean
//
//  Created by Matthieu Misiraca on 02/09/2026.
//

import SwiftUI
import UserNotifications

@main
struct MisiCleanApp: App {
    @State private var diskInfo = DiskInfo.load()

    init() {
        startDiskMonitoring()
    }

    var body: some Scene {
        Window("MisiClean", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarPanel()
        } label: {
            MenuBarStatusLabel(diskInfo: diskInfo)
        }
        .menuBarExtraStyle(.window)
    }

    // Vérifie l'espace disque toutes les 5 minutes et notifie si critique (>90%)
    private func startDiskMonitoring() {
        Task.detached(priority: .background) {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await MisiCleanApp.checkDiskAndNotify()
            }
        }
    }

    @MainActor
    static func checkDiskAndNotify() {
        let info = DiskInfo.load()
        guard info.usedFraction > 0.90 else { return }

        // Throttle: pas plus d'une notification toutes les 4 heures
        let lastKey = "fr.misilab.MisiClean.lastDiskNotification"
        if let last = UserDefaults.standard.object(forKey: lastKey) as? Date,
           Date().timeIntervalSince(last) < 4 * 3600 { return }
        UserDefaults.standard.set(Date(), forKey: lastKey)

        let content = UNMutableNotificationContent()
        content.title = "Espace disque critique"
        content.body = "Seulement \(info.availableBytes.formattedSize) disponibles (\(Int(info.usedFraction * 100))% utilisé). Ouvrez MisiClean pour libérer de l'espace."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "fr.misilab.MisiClean.diskWarning",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
