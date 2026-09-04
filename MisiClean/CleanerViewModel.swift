//
//  CleanerViewModel.swift
//  MisiClean
//

import Foundation
import SwiftUI
import Combine

@MainActor
class CleanerViewModel: ObservableObject {
    @Published var categories: [CleanCategory] = CleanerViewModel.defaultCategories()
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var diskInfo: DiskInfo = .load()
    @Published var showConfirmation = false
    @Published var showResult = false
    @Published var lastCleanedBytes: Int64 = 0
    @Published var hasErrors = false
    @Published var lastScanDate: Date? = nil
    @Published var isQuickCleaning = false

    var totalSelectedBytes: Int64 {
        categories.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }
    var hasResults: Bool { categories.contains { $0.sizeBytes > 0 } }
    var selectedCategories: [CleanCategory] { categories.filter(\.isSelected) }
    var maxCategorySize: Int64 { categories.max { $0.sizeBytes < $1.sizeBytes }?.sizeBytes ?? 1 }

    // MARK: - Default categories

    static func defaultCategories() -> [CleanCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let lib  = home.appendingPathComponent("Library")
        return [
            // Système
            CleanCategory(name: "Caches utilisateur",
                          description: "Fichiers de cache des applications",
                          icon: "internaldrive", accent: .blue,
                          paths: [lib.appendingPathComponent("Caches")]),
            CleanCategory(name: "Journaux & Crashes",
                          description: "Logs et rapports de plantage",
                          icon: "exclamationmark.triangle.fill", accent: .orange,
                          paths: [lib.appendingPathComponent("Logs")]),
            CleanCategory(name: "Mail",
                          description: "Cache de l'application Mail Apple",
                          icon: "envelope.fill", accent: Color(red: 0.2, green: 0.5, blue: 0.9),
                          paths: [lib.appendingPathComponent("Containers/com.apple.mail/Data/Library/Caches")]),
            CleanCategory(name: "Corbeille",
                          description: "Fichiers en attente de suppression définitive",
                          icon: "trash.fill", accent: .red,
                          paths: [home.appendingPathComponent(".Trash")]),
            // Développement
            CleanCategory(name: "Xcode — Derived Data",
                          description: "Index et binaires de compilation Xcode",
                          icon: "hammer.fill", accent: .purple,
                          paths: [lib.appendingPathComponent("Developer/Xcode/DerivedData")]),
            CleanCategory(name: "Xcode — Archives",
                          description: "Archives d'applications exportées",
                          icon: "shippingbox.fill", accent: .indigo,
                          paths: [lib.appendingPathComponent("Developer/Xcode/Archives")]),
            CleanCategory(name: "Simulateurs iOS",
                          description: "Cache des simulateurs iOS / watchOS / tvOS",
                          icon: "iphone", accent: .cyan,
                          paths: [lib.appendingPathComponent("Developer/CoreSimulator/Caches")]),
            CleanCategory(name: "CocoaPods",
                          description: "Cache du gestionnaire de dépendances",
                          icon: "tray.full.fill", accent: .teal,
                          paths: [lib.appendingPathComponent("Caches/CocoaPods")]),
            CleanCategory(name: "SPM cache",
                          description: "Cache Swift Package Manager",
                          icon: "cube.box.fill", accent: .mint,
                          paths: [lib.appendingPathComponent("org.swift.swiftpm")]),
            CleanCategory(name: "Homebrew",
                          description: "Cache du gestionnaire Homebrew",
                          icon: "leaf.fill", accent: .brown,
                          paths: [lib.appendingPathComponent("Caches/Homebrew")]),
            CleanCategory(name: "npm cache",
                          description: "Cache du gestionnaire de paquets Node.js",
                          icon: "shippingbox", accent: .green,
                          paths: [home.appendingPathComponent(".npm/_cacache")]),
            // Appareils & Navigateurs
            CleanCategory(name: "iOS Device Support",
                          description: "Symboles de débogage appareils iOS / watchOS / tvOS",
                          icon: "iphone.badge.play", accent: Color(red: 0.1, green: 0.6, blue: 0.9),
                          paths: [
                            lib.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"),
                            lib.appendingPathComponent("Developer/Xcode/watchOS DeviceSupport"),
                            lib.appendingPathComponent("Developer/Xcode/tvOS DeviceSupport"),
                            lib.appendingPathComponent("Developer/Xcode/visionOS DeviceSupport"),
                          ]),
            CleanCategory(name: "iOS Backups",
                          description: "Sauvegardes iPhone et iPad",
                          icon: "iphone.and.arrow.forward", accent: Color(red: 0.0, green: 0.5, blue: 1.0),
                          paths: [lib.appendingPathComponent("Application Support/MobileSync/Backup")]),
            CleanCategory(name: "Safari",
                          description: "Cache et données du navigateur Safari",
                          icon: "safari.fill", accent: .blue,
                          paths: [lib.appendingPathComponent("Caches/com.apple.Safari")]),
            CleanCategory(name: "Chrome",
                          description: "Cache du navigateur Google Chrome",
                          icon: "globe", accent: Color(red: 0.26, green: 0.52, blue: 0.96),
                          paths: chromeCachePaths()),
            CleanCategory(name: "Firefox",
                          description: "Cache du navigateur Firefox",
                          icon: "flame.fill", accent: Color(red: 0.9, green: 0.4, blue: 0.1),
                          paths: firefoxCachePaths()),
        ]
    }

    private static func chromeCachePaths() -> [URL] {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")
        guard let profiles = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
        else { return [] }
        return profiles.flatMap {
            [$0.appendingPathComponent("Cache"), $0.appendingPathComponent("Code Cache")]
        }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func firefoxCachePaths() -> [URL] {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")
        guard let profiles = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
        else { return [] }
        return profiles.map { $0.appendingPathComponent("cache2") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Scan

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer {
            isScanning = false
            diskInfo = .load()
        }

        for i in categories.indices {
            categories[i].sizeBytes = 0; categories[i].fileCount = 0
            categories[i].isSelected = false; categories[i].isScanning = true
        }

        let pathsSnapshot = categories.map(\.paths)

        await withTaskGroup(of: (Int, Int64, Int).self) { group in
            for (idx, paths) in pathsSnapshot.enumerated() {
                group.addTask {
                    var s: Int64 = 0; var c = 0
                    for p in paths { let (ps, pc) = CleanerViewModel.measureFolder(p); s += ps; c += pc }
                    return (idx, s, c)
                }
            }
            for await (idx, size, count) in group {
                withAnimation(.easeOut(duration: 0.35)) {
                    categories[idx].sizeBytes = size
                    categories[idx].fileCount = count
                    categories[idx].isSelected = size > 0
                    categories[idx].isScanning = false
                }
            }
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
            categories.sort { $0.sizeBytes > $1.sizeBytes }
        }
        lastScanDate = Date()
    }

    nonisolated static func measureFolder(_ url: URL) -> (Int64, Int) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return (0, 0) }
        var size: Int64 = 0; var count = 0
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return (0, 0) }
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            size += Int64(v.fileSize ?? 0); count += 1
        }
        return (size, count)
    }

    // MARK: - Clean

    func requestClean() {
        guard totalSelectedBytes > 0 else { return }
        showConfirmation = true
    }

    func clean() async {
        guard !isCleaning else { return }
        isCleaning = true
        defer {
            isCleaning = false
            diskInfo = .load()
        }

        hasErrors = false
        var freed: Int64 = 0
        var hadError = false
        let cleanedNames = selectedCategories.map(\.name)

        for i in categories.indices where categories[i].isSelected {
            let sizeBefore = categories[i].sizeBytes
            var deletedAll = true
            for path in categories[i].paths {
                if await deleteContents(of: path) != nil {
                    hadError = true; deletedAll = false
                }
            }
            freed += deletedAll ? sizeBefore : 0
            withAnimation {
                categories[i].sizeBytes = 0
                categories[i].fileCount = 0
                categories[i].isSelected = false
            }
        }

        lastCleanedBytes = freed
        hasErrors = hadError
        HistoryManager.shared.record(freedBytes: freed, categoryNames: cleanedNames)
        showResult = true
    }

    private func deleteContents(of url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard fm.fileExists(atPath: url.path),
                  let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            else { return nil }
            var lastError: String?
            for item in contents { do { try fm.removeItem(at: item) } catch { lastError = error.localizedDescription } }
            return lastError
        }.value
    }

    // MARK: - Quick Clean

    func quickClean() async {
        guard !isCleaning && !isScanning && !isQuickCleaning else { return }
        isQuickCleaning = true
        defer { isQuickCleaning = false; diskInfo = .load() }

        let safeNames = PreferencesManager.shared.quickCleanCategoryNames
        let targets = categories.enumerated().filter { safeNames.contains($0.element.name) }

        // Measure sizes in parallel
        var sizeMap: [Int: Int64] = [:]
        await withTaskGroup(of: (Int, Int64).self) { group in
            for (idx, cat) in targets {
                group.addTask {
                    var s: Int64 = 0
                    for p in cat.paths { s += CleanerViewModel.measureFolder(p).0 }
                    return (idx, s)
                }
            }
            for await (idx, size) in group { sizeMap[idx] = size }
        }

        // Clean non-empty categories
        var freed: Int64 = 0
        var cleanedNames: [String] = []
        for (idx, cat) in targets {
            let size = sizeMap[idx] ?? 0
            guard size > 0 else { continue }
            var ok = true
            for path in cat.paths { if await deleteContents(of: path) != nil { ok = false } }
            if ok { freed += size }
            cleanedNames.append(cat.name)
            withAnimation {
                categories[idx].sizeBytes = 0
                categories[idx].fileCount = 0
                categories[idx].isSelected = false
            }
        }

        lastCleanedBytes = freed
        hasErrors = false
        if freed > 0 { HistoryManager.shared.record(freedBytes: freed, categoryNames: cleanedNames) }
        showResult = true
    }

    func setSelectAll(_ value: Bool) {
        withAnimation {
            for i in categories.indices where categories[i].sizeBytes > 0 { categories[i].isSelected = value }
        }
    }
}
