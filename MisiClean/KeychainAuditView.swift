//
//  KeychainAuditView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine
import Security

// MARK: - Model

struct KeychainItem: Identifiable {
    let id = UUID()
    let itemClass: KeychainItemClass
    let service: String      // kSecAttrService or kSecAttrServer
    let account: String      // kSecAttrAccount
    let label: String        // kSecAttrLabel, fallback to service
    let createdDate: Date?
    let modifiedDate: Date?
    var isSelected = false
}

enum KeychainItemClass: String, CaseIterable {
    case internet = "Internet"
    case generic  = "Application"
}

// MARK: - ViewModel

@MainActor final class KeychainAuditViewModel: ObservableObject {
    @Published var items: [KeychainItem] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var selectedClass: KeychainItemClass? = nil

    var displayed: [KeychainItem] {
        let src = selectedClass == nil
            ? items
            : items.filter { $0.itemClass == selectedClass }
        return src.sorted { $0.service.localizedCompare($1.service) == .orderedAscending }
    }

    var selectedCount: Int {
        items.filter(\.isSelected).count
    }

    var classCounts: [KeychainItemClass: Int] {
        var counts: [KeychainItemClass: Int] = [:]
        for cls in KeychainItemClass.allCases {
            counts[cls] = items.filter { $0.itemClass == cls }.count
        }
        return counts
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        hasLoaded = true

        let fetched = await Task.detached(priority: .userInitiated) {
            var result: [KeychainItem] = []

            // Internet passwords
            var internetResult: CFTypeRef?
            let internetQuery: [CFString: Any] = [
                kSecClass: kSecClassInternetPassword,
                kSecReturnAttributes: true,
                kSecMatchLimit: kSecMatchLimitAll,
                kSecUseAuthenticationUI: kSecUseAuthenticationUISkip,
            ]
            let internetStatus = SecItemCopyMatching(internetQuery as CFDictionary, &internetResult)
            if internetStatus == errSecSuccess,
               let dicts = internetResult as? [[CFString: Any]] {
                for dict in dicts {
                    let service = (dict[kSecAttrServer] as? String) ?? ""
                    let account = (dict[kSecAttrAccount] as? String) ?? ""
                    guard !service.isEmpty || !account.isEmpty else { continue }
                    let rawLabel = (dict[kSecAttrLabel] as? String) ?? ""
                    let label = rawLabel.isEmpty ? service : rawLabel
                    let created = dict[kSecAttrCreationDate] as? Date
                    let modified = dict[kSecAttrModificationDate] as? Date
                    result.append(KeychainItem(
                        itemClass: .internet,
                        service: service,
                        account: account,
                        label: label,
                        createdDate: created,
                        modifiedDate: modified
                    ))
                }
            }

            // Generic passwords
            var genericResult: CFTypeRef?
            let genericQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecReturnAttributes: true,
                kSecMatchLimit: kSecMatchLimitAll,
                kSecUseAuthenticationUI: kSecUseAuthenticationUISkip,
            ]
            let genericStatus = SecItemCopyMatching(genericQuery as CFDictionary, &genericResult)
            if genericStatus == errSecSuccess,
               let dicts = genericResult as? [[CFString: Any]] {
                for dict in dicts {
                    let service = (dict[kSecAttrService] as? String) ?? ""
                    let account = (dict[kSecAttrAccount] as? String) ?? ""
                    guard !service.isEmpty || !account.isEmpty else { continue }
                    let rawLabel = (dict[kSecAttrLabel] as? String) ?? ""
                    let label = rawLabel.isEmpty ? service : rawLabel
                    let created = dict[kSecAttrCreationDate] as? Date
                    let modified = dict[kSecAttrModificationDate] as? Date
                    result.append(KeychainItem(
                        itemClass: .generic,
                        service: service,
                        account: account,
                        label: label,
                        createdDate: created,
                        modifiedDate: modified
                    ))
                }
            }

            return result
        }.value

        items = fetched
        isLoading = false
    }

    func deleteSelected() async {
        let toDelete = items.filter(\.isSelected)
        await Task.detached(priority: .userInitiated) {
            for item in toDelete {
                let secClass: CFString = item.itemClass == .internet
                    ? kSecClassInternetPassword
                    : kSecClassGenericPassword
                let serviceKey: CFString = item.itemClass == .internet
                    ? kSecAttrServer
                    : kSecAttrService
                let query: [CFString: Any] = [
                    kSecClass: secClass,
                    serviceKey: item.service,
                    kSecAttrAccount: item.account,
                ]
                SecItemDelete(query as CFDictionary)
            }
        }.value
        await load()
    }

    func toggle(_ id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isSelected.toggle()
        }
    }

    func setAll(_ on: Bool) {
        for idx in items.indices {
            items[idx].isSelected = on
        }
    }
}

// MARK: - Section View

struct KeychainAuditSection: View {
    @ObservedObject var vm: KeychainAuditViewModel
    @State private var showDeleteConfirm = false

    private let accent = Color(red: 0.35, green: 0.55, blue: 0.95)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Group {
                if vm.isLoading {
                    loadingView
                } else if !vm.hasLoaded {
                    initialView
                } else if vm.items.isEmpty {
                    emptyView
                } else {
                    mainContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            "Supprimer \(vm.selectedCount) entrée(s) ?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                Task { await vm.deleteSelected() }
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trousseau d'accès").font(.callout.weight(.semibold))
                if vm.hasLoaded && !vm.isLoading {
                    Text("\(vm.items.count) entrée(s) trouvée(s)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Identifiants stockés dans votre trousseau système")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if vm.isLoading { ProgressView().scaleEffect(0.7) }
            Button { Task { await vm.load() } } label: {
                Label("Analyser", systemImage: "key.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(vm.isLoading)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: States

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView("Lecture du trousseau…").scaleEffect(1.1)
            Spacer()
        }
    }

    private var initialView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(accent.opacity(0.10)).frame(width: 90, height: 90)
                Image(systemName: "key.fill")
                    .font(.system(size: 40, weight: .thin)).foregroundStyle(accent)
            }
            VStack(spacing: 8) {
                Text("Trousseau d'accès").font(.title3.bold())
                Text("Visualisez toutes les entrées stockées dans votre trousseau — mots de passe d'apps, comptes web, services — et supprimez celles dont vous n'avez plus besoin.")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            Button { Task { await vm.load() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                    Text("Analyser le trousseau")
                }
                .font(.title3.weight(.semibold)).foregroundStyle(.white)
                .frame(minWidth: 260).padding(.vertical, 14)
                .background(accent, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: accent.opacity(0.4), radius: 14, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(40)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "key.slash.fill")
                .font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.4))
            Text("Aucune entrée trouvée dans le trousseau")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Main content (class sidebar + list + footer)

    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                classFilterSidebar
                Divider()
                keychainList
            }
            if !vm.displayed.isEmpty {
                footer
            }
        }
    }

    // MARK: Class filter sidebar

    private var classFilterSidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Catégorie")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)

                KeychainClassRow(
                    label: "Tout",
                    icon: "list.bullet",
                    color: .secondary,
                    count: vm.items.count,
                    isSelected: vm.selectedClass == nil,
                    accent: accent
                ) { vm.selectedClass = nil }

                ForEach(KeychainItemClass.allCases, id: \.self) { cls in
                    let count = vm.classCounts[cls] ?? 0
                    let icon = cls == .internet ? "globe" : "app.fill"
                    KeychainClassRow(
                        label: cls.rawValue,
                        icon: icon,
                        color: accent,
                        count: count,
                        isSelected: vm.selectedClass == cls,
                        accent: accent
                    ) { vm.selectedClass = cls }
                }
            }
            .padding(.bottom, 8)
        }
        .frame(width: 190)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Keychain list

    private var keychainList: some View {
        let displayedItems = vm.displayed
        return ScrollView {
            if displayedItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 60)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40)).foregroundStyle(.green.opacity(0.6))
                    Text("Aucune entrée pour cette catégorie").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(displayedItems) { item in
                        KeychainItemRowView(
                            item: item,
                            accent: accent,
                            onToggle: { vm.toggle(item.id) }
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if vm.selectedCount > 0 {
                Text("\(vm.selectedCount) sélectionnée(s)")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Sélectionnez des entrées à supprimer")
                    .font(.callout).foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Tout sélectionner") { vm.setAll(true) }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .font(.callout)
            Button("Désélectionner") { vm.setAll(false) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
            Button {
                showDeleteConfirm = true
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(vm.selectedCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Class filter row

private struct KeychainClassRow: View {
    let label: String
    let icon: String
    let color: Color
    let count: Int
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? accent.opacity(0.2) : Color.secondary.opacity(0.08))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon)
                        .font(.system(size: 11)).foregroundStyle(isSelected ? accent : Color.secondary)
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
                          ? accent.opacity(0.12)
                          : hovering ? Color.secondary.opacity(0.06) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 8)
        .onHover { hovering = $0 }
    }
}

// MARK: - Keychain item row

private struct KeychainItemRowView: View {
    let item: KeychainItem
    let accent: Color
    let onToggle: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            // Selection toggle
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(item.isSelected ? accent : Color.secondary.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if item.isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .buttonStyle(.plain)

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(accent.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: item.itemClass == .internet ? "globe" : "app.fill")
                    .font(.system(size: 17)).foregroundStyle(accent)
            }

            // Service + account
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label.isEmpty ? item.service : item.label)
                    .font(.body.weight(.medium)).lineLimit(1)
                Text(item.account.isEmpty ? "—" : item.account)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            // Right side: class badge + date
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.itemClass.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))

                if let date = item.modifiedDate {
                    Text(Self.dateFormatter.string(from: date))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(
            item.isSelected
                ? accent.opacity(0.07)
                : Color.primary.opacity(0.03),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(item.isSelected ? accent.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
