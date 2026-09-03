//
//  Models.swift
//  MisiClean
//

import SwiftUI

// MARK: - Nettoyage

struct CleanCategory: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let accent: Color
    let paths: [URL]
    var sizeBytes: Int64 = 0
    var fileCount: Int = 0
    var isSelected: Bool = false
    var isScanning: Bool = false
}

// MARK: - Gros Fichiers

struct LargeFile: Identifiable {
    let id = UUID()
    let url: URL
    let sizeBytes: Int64
    let lastAccessedDate: Date?
    var isSelected: Bool = false

    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path }
}

// MARK: - Doublons

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let sizeBytes: Int64
    var files: [DuplicateFile]

    var wasteableBytes: Int64 { sizeBytes * Int64(max(0, files.count - 1)) }
    var selectedCount: Int { files.filter(\.isSelected).count }
    var bytesToDelete: Int64 { sizeBytes * Int64(selectedCount) }
}

struct DuplicateFile: Identifiable {
    let id = UUID()
    let url: URL
    var isSelected: Bool = false

    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path }
}

// MARK: - Scan Location

enum ScanLocation: String, CaseIterable, Identifiable {
    case downloads = "Téléchargements"
    case desktop   = "Bureau"
    case documents = "Documents"
    case pictures  = "Images"
    case home      = "Dossier personnel"
    case disk      = "Disque entier"

    var id: String { rawValue }

    var url: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .home:      return home
        case .downloads: return home.appendingPathComponent("Downloads")
        case .documents: return home.appendingPathComponent("Documents")
        case .desktop:   return home.appendingPathComponent("Desktop")
        case .pictures:  return home.appendingPathComponent("Pictures")
        case .disk:      return URL(fileURLWithPath: "/")
        }
    }
}

// MARK: - App Uninstaller

struct InstalledApp: Identifiable {
    let id = UUID()
    let url: URL
    let bundleID: String
    let version: String
    var leftovers: [URL] = []
    var leftoverBytes: Int64 = 0
    var appSizeBytes: Int64 = 0
    var lastUsedDate: Date? = nil
    var isLoadingLeftovers: Bool = true
    var isSelected: Bool = false

    var name: String { url.deletingPathExtension().lastPathComponent }
}

// MARK: - Login Items

struct LoginItem: Identifiable {
    let id = UUID()
    let label: String
    let programPath: String
    let plistURL: URL
    var isEnabled: Bool
    var isSystem: Bool

    var displayName: String {
        let url = URL(fileURLWithPath: programPath)
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? label : name
    }

    var appPath: String {
        var components = programPath.components(separatedBy: "/")
        while !components.isEmpty {
            let joined = components.joined(separator: "/")
            if joined.hasSuffix(".app") { return joined }
            components.removeLast()
        }
        return programPath
    }
}

// MARK: - Privacy

enum PrivacyAction {
    case clearClipboard
    case clearRecentItems
    case deletePaths([URL])
}

struct PrivacyItem: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let accent: Color
    let action: PrivacyAction
    var isSelected: Bool = false
    var sizeBytes: Int64 = 0
    var exists: Bool = true
}

// MARK: - Memory

struct MemoryInfo {
    let totalBytes: Int64
    let freeBytes: Int64
    let activeBytes: Int64
    let inactiveBytes: Int64
    let wiredBytes: Int64
    let compressedBytes: Int64

    var usedBytes: Int64 { activeBytes + wiredBytes + compressedBytes }
    var availableBytes: Int64 { freeBytes + inactiveBytes }
    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    static var zero: MemoryInfo {
        MemoryInfo(totalBytes: 0, freeBytes: 0, activeBytes: 0, inactiveBytes: 0, wiredBytes: 0, compressedBytes: 0)
    }
}

struct MemoryProcess: Identifiable {
    let id = UUID()
    let pid: Int
    let name: String
    let rssBytes: Int64
}

// MARK: - Extensions

extension Int64 {
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Date {
    var relativeFormatted: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Disk Info

struct DiskInfo {
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 { totalBytes - availableBytes }
    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    static func load() -> DiskInfo {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let vals = try? url.resourceValues(forKeys: keys)
        return DiskInfo(
            totalBytes: Int64(vals?.volumeTotalCapacity ?? 0),
            availableBytes: Int64(vals?.volumeAvailableCapacityForImportantUsage ?? 0)
        )
    }
}
