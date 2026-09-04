//
//  PreferencesManager.swift
//  MisiClean
//

import Foundation
import SwiftUI
import AppKit
import Combine
import ServiceManagement

@MainActor
final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    private enum K {
        static let menuBarOnly        = "fr.misilab.menuBarOnly"
        static let diskAlertThreshold = "fr.misilab.diskAlertThreshold"
        static let quickCleanData     = "fr.misilab.quickCleanData"
        static let excludedPaths      = "fr.misilab.excludedPaths"
        static let startInBackground  = "fr.misilab.startInBackground"
        static let autoCheckUpdates   = "fr.misilab.MisiClean.autoCheckUpdates"
    }

    @Published var menuBarOnly: Bool = false {
        didSet {
            UserDefaults.standard.set(menuBarOnly, forKey: K.menuBarOnly)
            NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
        }
    }

    @Published var diskAlertThreshold: Double = 0.90 {
        didSet { UserDefaults.standard.set(diskAlertThreshold, forKey: K.diskAlertThreshold) }
    }

    @Published var quickCleanCategoryNames: Set<String> = [
        "Caches utilisateur", "Journaux & Crashes", "Mail", "Corbeille",
        "CocoaPods", "SPM cache", "Homebrew", "npm cache",
    ] {
        didSet {
            if let data = try? JSONEncoder().encode(quickCleanCategoryNames) {
                UserDefaults.standard.set(data, forKey: K.quickCleanData)
            }
        }
    }

    @Published var excludedPaths: [URL] = [] {
        didSet { UserDefaults.standard.set(excludedPaths.map(\.path), forKey: K.excludedPaths) }
    }

    @Published var startInBackground: Bool = false {
        didSet { UserDefaults.standard.set(startInBackground, forKey: K.startInBackground) }
    }

    @Published var autoCheckUpdates: Bool = true {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: K.autoCheckUpdates) }
    }

    // Launch at login via SMAppService — no UserDefaults needed, macOS manages this
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else        { try SMAppService.mainApp.unregister() }
                objectWillChange.send()
            } catch {
                // Registration can fail if user has not granted permission yet;
                // macOS will prompt automatically on first attempt.
            }
        }
    }

    static let defaultQuickCleanCategories: Set<String> = [
        "Caches utilisateur", "Journaux & Crashes", "Mail", "Corbeille",
        "CocoaPods", "SPM cache", "Homebrew", "npm cache",
    ]

    static let quickCleanAllOptions: [String] = [
        "Caches utilisateur", "Journaux & Crashes", "Mail", "Corbeille",
        "CocoaPods", "SPM cache", "Homebrew", "npm cache",
        "Xcode — Derived Data", "Simulateurs iOS",
    ]

    private init() {
        let ud = UserDefaults.standard
        if ud.object(forKey: K.menuBarOnly) != nil {
            menuBarOnly = ud.bool(forKey: K.menuBarOnly)
        }
        let stored = ud.double(forKey: K.diskAlertThreshold)
        if stored > 0 { diskAlertThreshold = stored }
        if let data = ud.data(forKey: K.quickCleanData),
           let names = try? JSONDecoder().decode(Set<String>.self, from: data) {
            quickCleanCategoryNames = names
        }
        excludedPaths = (ud.stringArray(forKey: K.excludedPaths) ?? [])
            .map { URL(fileURLWithPath: $0) }
        if ud.object(forKey: K.startInBackground) != nil {
            startInBackground = ud.bool(forKey: K.startInBackground)
        }
        if ud.object(forKey: K.autoCheckUpdates) != nil {
            autoCheckUpdates = ud.bool(forKey: K.autoCheckUpdates)
        }
    }

    func addExclusion(_ url: URL) {
        guard !excludedPaths.contains(url) else { return }
        excludedPaths.append(url)
    }

    func removeExclusion(_ url: URL) {
        excludedPaths.removeAll { $0 == url }
    }

    func isExcluded(_ url: URL) -> Bool {
        excludedPaths.contains { url.path.hasPrefix($0.path) }
    }
}
