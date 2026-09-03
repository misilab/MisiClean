//
//  HistoryManager.swift
//  MisiClean
//

import Foundation
import Combine

struct CleanupEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    let freedBytes: Int64
    let categoryNames: [String]
}

@MainActor
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published var events: [CleanupEvent] = []

    private let storageKey = "fr.misilab.MisiClean.history"

    private init() { load() }

    func record(freedBytes: Int64, categoryNames: [String]) {
        guard freedBytes > 0 else { return }
        let event = CleanupEvent(id: UUID(), date: Date(), freedBytes: freedBytes, categoryNames: categoryNames)
        events.insert(event, at: 0)
        if events.count > 200 { events = Array(events.prefix(200)) }
        save()
    }

    func delete(_ event: CleanupEvent) {
        events.removeAll { $0.id == event.id }
        save()
    }

    func clearAll() {
        events = []
        save()
    }

    var totalFreedBytes: Int64 { events.reduce(0) { $0 + $1.freedBytes } }
    var cleanCount: Int { events.count }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CleanupEvent].self, from: data)
        else { return }
        events = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
