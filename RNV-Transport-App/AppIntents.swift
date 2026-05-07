//
//  AppIntents.swift
//  RNV-Transport-App
//

import AppIntents
import SwiftUI

// MARK: - Search Connections Intent

struct SearchConnectionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Verbindung suchen"
    static let description = IntentDescription("Öffnet die ÖPNV Mannheim App zur Verbindungssuche.")

    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Show Nearby Departures Intent

struct ShowNearbyDeparturesIntent: AppIntent {
    static let title: LocalizedStringResource = "Abfahrten in der Nähe"
    static let description = IntentDescription("Zeigt die nächsten Abfahrten von Haltestellen in deiner Nähe.")

    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Show Planned Trips Intent

struct ShowPlannedTripsIntent: AppIntent {
    static let title: LocalizedStringResource = "Geplante Fahrten anzeigen"
    static let description = IntentDescription("Zeigt aktive Live Activities und verfolgte Fahrten.")

    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct RNVAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchConnectionsIntent(),
            phrases: [
                "Verbindung suchen in \(.applicationName)",
                "Öffne \(.applicationName)"
            ],
            shortTitle: "Verbindung suchen",
            systemImageName: "tram.fill"
        )
        AppShortcut(
            intent: ShowNearbyDeparturesIntent(),
            phrases: [
                "Abfahrten in \(.applicationName) anzeigen",
                "Was fährt jetzt in \(.applicationName)"
            ],
            shortTitle: "Abfahrten in der Nähe",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: ShowPlannedTripsIntent(),
            phrases: [
                "Meine Fahrten in \(.applicationName)"
            ],
            shortTitle: "Geplante Fahrten",
            systemImageName: "bell.fill"
        )
    }
}
