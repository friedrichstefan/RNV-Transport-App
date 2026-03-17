//
//  SharedModels.swift
//  RNV-Transport-App
//
//  Zusammengeführt aus SharedModels.swift + LiveActivityState.swift
//

import Foundation
import ActivityKit

// MARK: - Activity Attributes

struct TripLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentLegIndex: Int
        var nextStopName: String
        var nextStopTime: String
        var estimatedTime: String?
        var delay: Int?
        var destination: String
        var lineName: String
        var serviceType: String
        var phase: TripPhase
    }

    var tripId: String
    var startStation: String
    var endStation: String
    var totalLegs: Int
    var departureTimeISO: String
    var arrivalTimeISO: String
}

// MARK: - Trip Phases

enum TripPhase: String, Codable, Hashable {
    case beforeDeparture
    case duringJourney
    case arrived
}

// MARK: - Live Activity State (App Group UserDefaults)

class LiveActivityState {
    static let shared = LiveActivityState()

    private let appGroupID = AppConfiguration.appGroupID
    private let activeTripsKey = "activeTrips"

    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    func setTripActive(_ tripId: String, isActive: Bool) {
        guard let defaults = userDefaults else {
            print("❌ [STATE] UserDefaults konnte nicht geladen werden")
            print("   Stelle sicher, dass App Groups in beiden Targets aktiviert sind!")
            return
        }

        var activeTrips = getActiveTrips()

        if isActive {
            if !activeTrips.contains(tripId) {
                activeTrips.append(tripId)
            }
        } else {
            activeTrips.removeAll { $0 == tripId }
        }

        defaults.set(activeTrips, forKey: activeTripsKey)
        defaults.synchronize()

        print("✅ [STATE] Trip \(String(tripId.prefix(8))) ist jetzt \(isActive ? "aktiv" : "inaktiv")")
        print("   Aktive Trips: \(activeTrips.count)")
    }

    func isTripActive(_ tripId: String) -> Bool {
        return getActiveTrips().contains(tripId)
    }

    func getAllActiveTrips() -> [String] {
        return getActiveTrips()
    }

    func deactivateAllTrips() {
        guard let defaults = userDefaults else {
            print("❌ [STATE] UserDefaults konnte nicht geladen werden")
            return
        }
        defaults.removeObject(forKey: activeTripsKey)
        defaults.synchronize()
        print("✅ [STATE] Alle Trips deaktiviert")
    }

    private func getActiveTrips() -> [String] {
        guard let defaults = userDefaults else {
            print("⚠️ [STATE] UserDefaults nicht verfügbar - Überprüfe App Groups")
            return []
        }
        return defaults.stringArray(forKey: activeTripsKey) ?? []
    }

    func debugPrintState() {
        let activeTrips = getActiveTrips()
        print("🔍 [DEBUG] Live Activity State:")
        print("   - App Group ID: \(appGroupID)")
        print("   - Aktive Trips: \(activeTrips.count)")
        for trip in activeTrips {
            print("     • \(String(trip.prefix(12)))")
        }
    }
}