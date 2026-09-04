//
//  ScheduledCleaningView.swift
//  MisiClean
//

import SwiftUI
import UserNotifications
import Combine

// MARK: - Model

enum CleanFrequency: String, CaseIterable, Identifiable {
    case daily   = "Quotidien"
    case weekly  = "Hebdomadaire"
    case monthly = "Mensuel"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .daily:   return "sun.max.fill"
        case .weekly:  return "calendar"
        case .monthly: return "calendar.badge.clock"
        }
    }
    var description: String {
        switch self {
        case .daily:   return "Chaque jour à 9h"
        case .weekly:  return "Chaque lundi à 9h"
        case .monthly: return "Le 1er du mois à 9h"
        }
    }
}

// MARK: - ViewModel

@MainActor
class ScheduledCleaningViewModel: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "schedule.enabled")
            if isEnabled { scheduleNotification() } else { cancelAll() }
            updateNextDate()
        }
    }
    @Published var frequency: CleanFrequency {
        didSet {
            UserDefaults.standard.set(frequency.rawValue, forKey: "schedule.frequency")
            if isEnabled { scheduleNotification() }
            updateNextDate()
        }
    }
    @Published var permission: UNAuthorizationStatus = .notDetermined
    @Published var lastRun: Date?
    @Published var nextDate: Date?

    init() {
        let enabled  = UserDefaults.standard.bool(forKey: "schedule.enabled")
        let freqRaw  = UserDefaults.standard.string(forKey: "schedule.frequency") ?? CleanFrequency.weekly.rawValue
        self.isEnabled  = enabled
        self.frequency  = CleanFrequency(rawValue: freqRaw) ?? .weekly
        self.lastRun    = UserDefaults.standard.object(forKey: "schedule.lastRun") as? Date
        updateNextDate()
    }

    func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permission = settings.authorizationStatus
    }

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            permission = granted ? .authorized : .denied
            if granted && isEnabled { scheduleNotification() }
        } catch {
            permission = .denied
        }
    }

    func recordRun() {
        let now = Date()
        lastRun = now
        UserDefaults.standard.set(now, forKey: "schedule.lastRun")
    }

    private func scheduleNotification() {
        cancelAll()
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "MisiClean — Temps de nettoyer"
        content.body  = "Votre nettoyage \(frequency.rawValue.lowercased()) est prêt à lancer."
        content.sound = .default

        var dc = DateComponents()
        dc.hour = 9; dc.minute = 0

        let trigger: UNCalendarNotificationTrigger
        switch frequency {
        case .daily:
            trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        case .weekly:
            dc.weekday = 2
            trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        case .monthly:
            dc.day = 1
            trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        }

        let req = UNNotificationRequest(identifier: "misiclean.schedule",
                                        content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    private func cancelAll() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["misiclean.schedule"])
    }

    private func updateNextDate() {
        guard isEnabled else { nextDate = nil; return }
        let cal = Calendar.current
        var dc  = DateComponents(); dc.hour = 9; dc.minute = 0
        switch frequency {
        case .daily:   break
        case .weekly:  dc.weekday = 2
        case .monthly: dc.day = 1
        }
        nextDate = cal.nextDate(after: Date(), matching: dc, matchingPolicy: .nextTime)
    }
}

// MARK: - Section View

struct ScheduledCleaningSection: View {
    @ObservedObject var vm: ScheduledCleaningViewModel
    private let accent = Color(red: 0.5, green: 0.28, blue: 0.92)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    toggleCard
                    frequencyCard
                    statusCard
                    tipsCard
                }
                .padding(16)
            }
        }
        .onAppear { Task { await vm.checkPermission() } }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Planification").font(.callout.weight(.semibold))
                Text("Nettoyage automatique planifié")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var toggleCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nettoyage automatique").font(.callout.weight(.semibold))
                    Text("Reçois une notification quand c'est l'heure de nettoyer")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $vm.isEnabled).toggleStyle(.switch).labelsHidden()
            }
            .padding(16)

            if vm.isEnabled {
                if vm.permission == .denied {
                    Divider()
                    notificationBanner(
                        icon: "bell.slash.fill", color: .orange,
                        title: "Notifications désactivées",
                        subtitle: "Activez-les dans Réglages Système → Notifications",
                        action: {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                        }, actionLabel: "Réglages"
                    )
                } else if vm.permission == .notDetermined {
                    Divider()
                    notificationBanner(
                        icon: "bell.fill", color: .blue,
                        title: "Autoriser les notifications",
                        subtitle: "Nécessaire pour les rappels de nettoyage",
                        action: { Task { await vm.requestPermission() } },
                        actionLabel: "Autoriser"
                    )
                }
            }
        }
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private func notificationBanner(icon: String, color: Color, title: String,
                                     subtitle: String, action: @escaping () -> Void,
                                     actionLabel: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionLabel, action: action)
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(12)
        .background(color.opacity(0.07))
    }

    private var frequencyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fréquence")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)

            HStack(spacing: 8) {
                ForEach(CleanFrequency.allCases) { freq in
                    Button { withAnimation(.spring(response: 0.3)) { vm.frequency = freq } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: freq.icon)
                                .font(.title2)
                                .foregroundStyle(vm.frequency == freq ? .white : accent)
                            Text(freq.rawValue)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(vm.frequency == freq ? .white : .primary)
                            Text(freq.description)
                                .font(.caption2)
                                .foregroundStyle(vm.frequency == freq ? .white.opacity(0.8) : .secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14).padding(.horizontal, 6)
                        .background(
                            vm.frequency == freq ? accent : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.isEnabled)
                    .opacity(vm.isEnabled ? 1.0 : 0.45)
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusCard: some View {
        VStack(spacing: 0) {
            if let next = vm.nextDate {
                statusRow(icon: "clock.arrow.circlepath", color: accent,
                          label: "Prochain rappel",
                          value: next.formatted(date: .abbreviated, time: .shortened))
            }
            if let last = vm.lastRun {
                if vm.nextDate != nil { Divider().padding(.horizontal, 16) }
                statusRow(icon: "checkmark.circle.fill", color: .green,
                          label: "Dernier nettoyage",
                          value: last.formatted(date: .abbreviated, time: .shortened))
                Divider().padding(.horizontal, 16)
            }
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(.blue)
                Text("Nettoyer maintenant").font(.callout)
                Spacer()
                Button("Lancer") { vm.recordRun() }
                    .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(label).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospacedDigit())
        }
        .padding(16)
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Conseils", systemImage: "lightbulb.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)

            tipRow("Un nettoyage hebdomadaire est recommandé pour la plupart des utilisateurs.")
            tipRow("Le nettoyage mensuel suffit si vous utilisez peu votre Mac.")
            tipRow("Vous recevrez une notification à 9h le jour planifié.")
        }
        .padding(16)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 4, height: 4).padding(.top, 6)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
