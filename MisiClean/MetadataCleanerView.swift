//
//  MetadataCleanerView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine
import CoreGraphics
import ImageIO

// MARK: - Model

struct ImageWithGPS: Identifiable {
    let id = UUID()
    let url: URL
    let latitude: Double
    let longitude: Double
    let sizeBytes: Int64
    var isSelected = false

    var name: String { url.lastPathComponent }

    var locationString: String {
        let latDir = latitude >= 0 ? "N" : "S"
        let lonDir = longitude >= 0 ? "E" : "O"
        return String(format: "%.4f°%@ %.4f°%@", abs(latitude), latDir, abs(longitude), lonDir)
    }

    var folderDisplay: String {
        let dir = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir.hasPrefix(home) {
            return "~" + dir.dropFirst(home.count)
        }
        return dir
    }
}

// MARK: - ViewModel

@MainActor
final class MetadataCleanerViewModel: ObservableObject {
    @Published var images: [ImageWithGPS] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var isCleaning = false
    @Published var cleanedCount = 0

    var totalSelected: Int { images.filter(\.isSelected).count }

    // MARK: Scan

    func scan() async {
        isScanning = true
        hasScanned = false
        images = []

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Documents"),
        ]
        // Uniquement les formats qu'ImageIO peut réécrire sans perte de données
        // Les formats RAW propriétaires (CR2, NEF, ARW…) sont lisibles mais pas ré-écrits par CGImageDestination
        let exts: Set<String> = ["jpg", "jpeg", "heic", "heif", "tiff", "tif", "png"]

        let found: [ImageWithGPS] = await Task.detached(priority: .userInitiated) {
            var urls: [URL] = []
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]

            for root in roots {
                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: options
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    // Limit depth to ~5 levels
                    let rootComponents = root.pathComponents.count
                    let fileComponents = fileURL.pathComponents.count
                    if fileComponents - rootComponents > 5 {
                        enumerator.skipDescendants()
                        continue
                    }
                    let ext = fileURL.pathExtension.lowercased()
                    guard exts.contains(ext) else { continue }
                    urls.append(fileURL)
                }
            }

            var results: [ImageWithGPS] = []
            await withTaskGroup(of: ImageWithGPS?.self) { group in
                for url in urls {
                    group.addTask {
                        MetadataCleanerViewModel.imageGPS(url)
                    }
                }
                for await item in group {
                    if let item { results.append(item) }
                }
            }
            results.sort { $0.sizeBytes > $1.sizeBytes }
            return results
        }.value

        images = found
        isScanning = false
        hasScanned = true
    }

    // MARK: Strip Selected

    func stripSelected() async {
        isCleaning = true
        let selected = images.filter(\.isSelected)

        let count = await withTaskGroup(of: Bool.self) { group -> Int in
            for image in selected {
                let url = image.url
                group.addTask {
                    MetadataCleanerViewModel.stripGPS(from: url)
                }
            }
            var successCount = 0
            for await success in group {
                if success { successCount += 1 }
            }
            return successCount
        }

        cleanedCount = count
        isCleaning = false
        await scan()
    }

    // MARK: Selection helpers

    func toggle(_ id: UUID) {
        if let idx = images.firstIndex(where: { $0.id == id }) {
            images[idx].isSelected.toggle()
        }
    }

    func setAll(_ on: Bool) {
        for idx in images.indices {
            images[idx].isSelected = on
        }
    }

    // MARK: GPS extraction (nonisolated, runs off main actor)

    nonisolated static func imageGPS(_ url: URL) -> ImageWithGPS? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let gpsDic = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        else { return nil }

        guard let latRaw = gpsDic[kCGImagePropertyGPSLatitude] as? Double,
              let lonRaw = gpsDic[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }

        let latRef = (gpsDic[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
        let lonRef = (gpsDic[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
        let lat = latRef.uppercased() == "S" ? -latRaw : latRaw
        let lon = lonRef.uppercased() == "W" ? -lonRaw : lonRaw

        let size: Int64
        if let res = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let s = res.fileSize {
            size = Int64(s)
        } else {
            size = 0
        }

        return ImageWithGPS(url: url, latitude: lat, longitude: lon, sizeBytes: size)
    }

    // MARK: GPS stripping (nonisolated, runs off main actor)

    nonisolated static func stripGPS(from url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let uti = CGImageSourceGetType(src)
        else { return false }

        let dir = url.deletingLastPathComponent()
        let tmpName = ".__mc_tmp_" + url.lastPathComponent
        let tmpURL = dir.appendingPathComponent(tmpName)

        guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, uti, CGImageSourceGetCount(src), nil)
        else { return false }

        let cleanMeta = CGImageMetadataCreateMutable()
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: cleanMeta,
            kCGImageDestinationMergeMetadata: false,
        ]

        for i in 0..<CGImageSourceGetCount(src) {
            CGImageDestinationAddImageFromSource(dest, src, i, options as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: tmpURL)
            return false
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            return false
        }
    }
}

// MARK: - View

struct MetadataCleanerSection: View {
    @ObservedObject var vm: MetadataCleanerViewModel
    @State private var showResult = false

    private let accent = Color(red: 0.88, green: 0.30, blue: 0.50)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                if vm.isCleaning {
                    cleaningState
                        .transition(.opacity)
                } else if vm.isScanning {
                    scanningState
                        .transition(.opacity)
                } else if !vm.hasScanned {
                    idleState
                        .transition(.opacity)
                } else if vm.images.isEmpty {
                    emptyState
                        .transition(.opacity)
                } else {
                    resultsList
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: vm.isScanning)
            .animation(.easeInOut(duration: 0.22), value: vm.isCleaning)
            .animation(.easeInOut(duration: 0.22), value: vm.hasScanned)
            .animation(.easeInOut(duration: 0.22), value: vm.images.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showResult) { resultSheet }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nettoyeur de métadonnées")
                    .font(.headline.weight(.semibold))
                if vm.hasScanned && !vm.images.isEmpty {
                    Text("\(vm.images.count) photo\(vm.images.count > 1 ? "s" : "") avec GPS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if vm.isScanning {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.trailing, 4)
            }
            Button {
                Task { await vm.scan() }
            } label: {
                Label("Scanner", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(vm.isScanning || vm.isCleaning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: States

    private var idleState: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(accent.opacity(0.10))
                    .frame(width: 90, height: 90)
                Circle()
                    .stroke(accent.opacity(0.20), lineWidth: 1.5)
                    .frame(width: 90, height: 90)
                Image(systemName: "location.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(accent)
            }
            VStack(spacing: 8) {
                Text("Nettoyeur GPS")
                    .font(.title2.weight(.bold))
                Text("Détecte les photos contenant des coordonnées GPS\net les supprime proprement — sans perte de qualité.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await vm.scan() }
            } label: {
                Label("Scanner les photos", systemImage: "location.magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 240)
                    .padding(.vertical, 14)
                    .background(accent, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: accent.opacity(0.45), radius: 12, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView("Analyse des photos…")
                .progressViewStyle(.circular)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cleaningState: some View {
        VStack(spacing: 16) {
            ProgressView("Suppression des données GPS…")
                .progressViewStyle(.circular)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.10))
                    .frame(width: 90, height: 90)
                Circle()
                    .stroke(Color.green.opacity(0.20), lineWidth: 1.5)
                    .frame(width: 90, height: 90)
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.green)
            }
            VStack(spacing: 6) {
                Text("Aucune photo avec GPS")
                    .font(.title2.weight(.bold))
                Text("Vos photos ne contiennent pas de coordonnées GPS\ndétectables dans les dossiers analysés.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Results list

    private var resultsList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(vm.images) { image in
                    imageRow(image)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.toggle(image.id) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider()
            footer
        }
    }

    private func imageRow(_ image: ImageWithGPS) -> some View {
        HStack(spacing: 12) {
            // Checkbox
            ZStack {
                Circle()
                    .strokeBorder(
                        image.isSelected ? accent : Color.secondary.opacity(0.35),
                        lineWidth: image.isSelected ? 2 : 1.5
                    )
                    .frame(width: 22, height: 22)
                if image.isSelected {
                    Circle()
                        .fill(accent)
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .animation(.spring(response: 0.25), value: image.isSelected)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(image.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(image.folderDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // GPS + size
            VStack(alignment: .trailing, spacing: 3) {
                Label(image.locationString, systemImage: "location.fill")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Text(image.sizeBytes.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(image.isSelected ? accent.opacity(0.07) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(image.isSelected ? accent.opacity(0.30) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Tout sélectionner") { vm.setAll(true) }
                Button("Tout désélectionner") { vm.setAll(false) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if vm.totalSelected > 0 {
                Text("\(vm.totalSelected) sélectionné\(vm.totalSelected > 1 ? "s" : "")")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Spacer()

            Button {
                Task {
                    await vm.stripSelected()
                    showResult = true
                }
            } label: {
                Label("Supprimer les données GPS", systemImage: "location.slash")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(vm.totalSelected > 0 ? accent : Color.secondary.opacity(0.25))
                    )
                    .shadow(
                        color: vm.totalSelected > 0 ? accent.opacity(0.40) : .clear,
                        radius: 8, x: 0, y: 3
                    )
            }
            .buttonStyle(.plain)
            .disabled(vm.totalSelected == 0 || vm.isCleaning || vm.isScanning)
            .animation(.easeInOut(duration: 0.18), value: vm.totalSelected)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Result sheet

    private var resultSheet: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 90, height: 90)
                    Circle()
                        .stroke(Color.green.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 90, height: 90)
                    Image(systemName: "location.slash.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.green)
                }

                VStack(spacing: 6) {
                    Text("\(vm.cleanedCount) photo\(vm.cleanedCount > 1 ? "s" : "") nettoyée\(vm.cleanedCount > 1 ? "s" : "")")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green, Color(red: 0.10, green: 0.65, blue: 0.40)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    Text("Les coordonnées GPS ont été supprimées\nsans perte de qualité.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            Button("Fermer") { showResult = false }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.large)
                .keyboardShortcut(.return)
                .padding(.bottom, 36)
        }
        .frame(width: 340, height: 340)
    }
}

#Preview {
    MetadataCleanerSection(vm: MetadataCleanerViewModel())
        .frame(width: 880, height: 620)
}
