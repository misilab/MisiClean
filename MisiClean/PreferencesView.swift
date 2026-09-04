//
//  PreferencesView.swift
//  MisiClean
//

import SwiftUI
import AppKit
import Combine

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPrefsTab()
                .tabItem { Label("Général", systemImage: "gearshape") }
                .tag(0)
            ExclusionsPrefsTab()
                .tabItem { Label("Exclusions", systemImage: "minus.circle") }
                .tag(1)
            NotificationsPrefsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(2)
            UpdatesPrefsTab()
                .tabItem { Label("Mises à jour", systemImage: "arrow.up.circle") }
                .tag(3)
        }
        .frame(width: 520, height: 430)
        .padding(.top, 10)
    }
}

// MARK: - Général

private struct GeneralPrefsTab: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    var body: some View {
        Form {
            Section("Démarrage") {
                Toggle("Lancer au démarrage de la session", isOn: Binding(
                    get: { prefs.launchAtLogin },
                    set: { prefs.launchAtLogin = $0 }
                ))
                Toggle("Démarrer en arrière-plan (sans fenêtre)", isOn: $prefs.startInBackground)
                    .disabled(!prefs.launchAtLogin)
                Text("La fenêtre principale reste ouvrable depuis l'icône dans la barre des menus.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Affichage") {
                Toggle("Menu bar uniquement (masquer du Dock)", isOn: $prefs.menuBarOnly)
                Text("MisiClean reste accessible depuis son icône dans la barre des menus.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Nettoyage rapide") {
                Text("Catégories incluses dans le bouton « Nettoyage rapide » :")
                    .font(.callout)
                ForEach(PreferencesManager.quickCleanAllOptions, id: \.self) { name in
                    let isOn = Binding<Bool>(
                        get: { prefs.quickCleanCategoryNames.contains(name) },
                        set: { enabled in
                            var s = prefs.quickCleanCategoryNames
                            if enabled { s.insert(name) } else { s.remove(name) }
                            prefs.quickCleanCategoryNames = s
                        }
                    )
                    Toggle(name, isOn: isOn).font(.callout)
                }
                Button("Remettre par défaut") {
                    prefs.quickCleanCategoryNames = PreferencesManager.defaultQuickCleanCategories
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }
}

// MARK: - Exclusions

private struct ExclusionsPrefsTab: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ces dossiers seront ignorés par tous les scans (gros fichiers, doublons, anciens fichiers).")
                .font(.callout).foregroundStyle(.secondary)

            Group {
                if prefs.excludedPaths.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 32, weight: .thin))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("Aucun dossier exclu").font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(prefs.excludedPaths, id: \.path) { url in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill").foregroundStyle(.secondary)
                                Text(url.path.replacingOccurrences(
                                    of: FileManager.default.homeDirectoryForCurrentUser.path,
                                    with: "~"
                                ))
                                .font(.callout).lineLimit(1)
                                Spacer()
                                Button {
                                    prefs.removeExclusion(url)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Color.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                }
            }
            .frame(minHeight: 140)

            HStack {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    panel.prompt = "Exclure"
                    if panel.runModal() == .OK {
                        for url in panel.urls { prefs.addExclusion(url) }
                    }
                } label: {
                    Label("Ajouter un dossier…", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                if !prefs.excludedPaths.isEmpty {
                    Button("Tout effacer") {
                        prefs.excludedPaths = []
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                    .font(.callout)
                }
            }
        }
        .padding(20)
    }
}

// MARK: - Mises à jour

private struct UpdatesPrefsTab: View {
    @ObservedObject private var prefs = PreferencesManager.shared
    @ObservedObject private var updater = SelfUpdateManager.shared

    private let accent = Color(red: 0.15, green: 0.72, blue: 0.38)

    var body: some View {
        Form {
            Section("Vérification automatique") {
                Toggle("Vérifier les mises à jour au démarrage", isOn: $prefs.autoCheckUpdates)
                Text("MisiClean vérifie une fois par jour si une nouvelle version est disponible.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("État") {
                HStack {
                    Text("Version installée")
                    Spacer()
                    Text(updater.currentVersion)
                        .foregroundStyle(.secondary)
                        .font(.callout.monospacedDigit())
                }

                if let update = updater.availableUpdate {
                    HStack {
                        Text("Nouvelle version")
                        Spacer()
                        Text(update.version)
                            .foregroundStyle(accent)
                            .font(.callout.monospacedDigit().weight(.semibold))
                    }
                    Button {
                        updater.openDownloadPage()
                    } label: {
                        Label("Télécharger MisiClean \(update.version)", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                } else if let last = updater.lastChecked {
                    HStack {
                        Text("Dernière vérification")
                        Spacer()
                        Text(last.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary).font(.caption)
                    }
                    if let err = updater.checkError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                    } else {
                        Label("Votre application est à jour", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
            }

            Section {
                HStack {
                    if updater.isChecking {
                        ProgressView().scaleEffect(0.7)
                    }
                    Button("Vérifier maintenant") {
                        Task { await updater.checkForUpdates() }
                    }
                    .disabled(updater.isChecking)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }
}

// MARK: - Notifications

private struct NotificationsPrefsTab: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    var body: some View {
        Form {
            Section("Alerte espace disque") {
                Picker("Alerter quand le disque est rempli à", selection: $prefs.diskAlertThreshold) {
                    Text("70%").tag(0.70)
                    Text("80%").tag(0.80)
                    Text("90%").tag(0.90)
                }
                .pickerStyle(.radioGroup)
                Text("Une notification s'affiche au maximum toutes les 4 heures.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }
}
