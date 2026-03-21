//
//  SharedModels.swift
//  RNV-Transport-App
//
//  Zusammengeführt aus SharedModels.swift + LiveActivityState.swift
//

import Foundation
import ActivityKit
import WidgetKit

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
    
    /// Serial Queue für Thread-sichere Zugriffe
    private let queue = DispatchQueue(label: "com.stefanfriedrich.rnvapp.liveactivitystate")

    /// Gecachte UserDefaults-Instanz (einmal erstellt statt bei jedem Zugriff)
    private let userDefaults: UserDefaults?
    
    /// Debounce-WorkItem für Widget-Reloads
    private var widgetReloadWorkItem: DispatchWorkItem?
    
    /// Notification die gepostet wird wenn sich aktive Trips ändern
    static let activeTripsDidChangeNotification = Notification.Name("LiveActivityStateActiveTripsDidChange")
    
    private init() {
        self.userDefaults = UserDefaults(suiteName: AppConfiguration.appGroupID)
    }
    
    // MARK: - Widget-Aktualisierung (debounced)
    
    private func scheduleWidgetReload() {
        widgetReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: "NextDepartureWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "ActiveTripsWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "QuickSearchWidget")
            #if DEBUG
            print("🔄 [WIDGET] Alle Widget-Timelines neu geladen (State-Änderung)")
            #endif
        }
        widgetReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    /// Benachrichtigt Beobachter über Änderungen an aktiven Trips
    private func notifyActiveTripsChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.activeTripsDidChangeNotification, object: nil)
        }
    }

    func setTripActive(_ tripId: String, isActive: Bool) {
        queue.sync {
            guard let defaults = userDefaults else {
                #if DEBUG
                print("❌ [STATE] UserDefaults konnte nicht geladen werden")
                print("   Stelle sicher, dass App Groups in beiden Targets aktiviert sind!")
                #endif
                return
            }

            var activeTrips = _getActiveTrips(defaults: defaults)

            if isActive {
                if !activeTrips.contains(tripId) {
                    activeTrips.append(tripId)
                }
            } else {
                activeTrips.removeAll { $0 == tripId }
            }

            defaults.set(activeTrips, forKey: activeTripsKey)

            #if DEBUG
            print("✅ [STATE] Trip \(String(tripId.prefix(8))) ist jetzt \(isActive ? "aktiv" : "inaktiv")")
            print("   Aktive Trips: \(activeTrips.count)")
            #endif
        }
        
        scheduleWidgetReload()
        notifyActiveTripsChanged()
    }

    func isTripActive(_ tripId: String) -> Bool {
        return queue.sync {
            guard let defaults = userDefaults else { return false }
            return _getActiveTrips(defaults: defaults).contains(tripId)
        }
    }

    func getAllActiveTrips() -> [String] {
        return queue.sync {
            guard let defaults = userDefaults else { return [] }
            return _getActiveTrips(defaults: defaults)
        }
    }

    func deactivateAllTrips() {
        queue.sync {
            guard let defaults = userDefaults else {
                #if DEBUG
                print("❌ [STATE] UserDefaults konnte nicht geladen werden")
                #endif
                return
            }
            defaults.removeObject(forKey: activeTripsKey)
            #if DEBUG
            print("✅ [STATE] Alle Trips deaktiviert")
            #endif
        }
        
        scheduleWidgetReload()
        notifyActiveTripsChanged()
    }

    /// Interne Hilfsmethode – muss innerhalb von `queue.sync` aufgerufen werden
    private func _getActiveTrips(defaults: UserDefaults) -> [String] {
        return defaults.stringArray(forKey: activeTripsKey) ?? []
    }

    // MARK: - Widget Trip-Daten speichern / entfernen

    private let savedTripDataKey = "savedTripData"

    /// Speichert Trip-Daten für die Home-Screen-Widgets in UserDefaults.
    func saveTripDataForWidget(_ widgetTrip: WidgetTripDataForApp) {
        queue.sync {
            guard let defaults = userDefaults else {
                #if DEBUG
                print("❌ [STATE] UserDefaults nicht verfügbar – Widget-Daten können nicht gespeichert werden")
                #endif
                return
            }

            var existingTrips = _loadWidgetTrips(defaults: defaults)

            // Vorhandenen Eintrag mit gleicher ID ersetzen
            existingTrips.removeAll { $0.id == widgetTrip.id }
            existingTrips.append(widgetTrip)

            do {
                let data = try JSONEncoder().encode(existingTrips)
                defaults.set(data, forKey: savedTripDataKey)
                #if DEBUG
                print("✅ [STATE] Widget-Daten gespeichert für Trip \(String(widgetTrip.id.prefix(8))) (\(existingTrips.count) gesamt)")
                #endif
            } catch {
                #if DEBUG
                print("❌ [STATE] Fehler beim Speichern der Widget-Daten: \(error)")
                #endif
            }
        }

        scheduleWidgetReload()
    }

    /// Entfernt Trip-Daten für einen bestimmten Trip aus den Widget-Daten.
    func removeTripDataForWidget(tripId: String) {
        queue.sync {
            guard let defaults = userDefaults else { return }

            var existingTrips = _loadWidgetTrips(defaults: defaults)
            existingTrips.removeAll { $0.id == tripId }

            do {
                let data = try JSONEncoder().encode(existingTrips)
                defaults.set(data, forKey: savedTripDataKey)
                #if DEBUG
                print("✅ [STATE] Widget-Daten entfernt für Trip \(String(tripId.prefix(8))) (\(existingTrips.count) verbleibend)")
                #endif
            } catch {
                #if DEBUG
                print("❌ [STATE] Fehler beim Entfernen der Widget-Daten: \(error)")
                #endif
            }
        }

        scheduleWidgetReload()
    }

    /// Entfernt alle Widget-Trip-Daten.
    func removeAllTripDataForWidget() {
        queue.sync {
            guard let defaults = userDefaults else { return }
            defaults.removeObject(forKey: savedTripDataKey)
            #if DEBUG
            print("✅ [STATE] Alle Widget-Daten entfernt")
            #endif
        }

        scheduleWidgetReload()
    }

    /// Interne Hilfsmethode – muss innerhalb von `queue.sync` aufgerufen werden
    private func _loadWidgetTrips(defaults: UserDefaults) -> [WidgetTripDataForApp] {
        guard let data = defaults.data(forKey: savedTripDataKey) else { return [] }
        do {
            return try JSONDecoder().decode([WidgetTripDataForApp].self, from: data)
        } catch {
            #if DEBUG
            print("⚠️ [STATE] Fehler beim Laden der Widget-Daten: \(error)")
            #endif
            return []
        }
    }

    func debugPrintState() {
        #if DEBUG
        let activeTrips = getAllActiveTrips()
        print("🔍 [DEBUG] Live Activity State:")
        print("   - App Group ID: \(appGroupID)")
        print("   - Aktive Trips: \(activeTrips.count)")
        for trip in activeTrips {
            print("     • \(String(trip.prefix(12)))")
        }
        let widgetTrips = queue.sync {
            guard let defaults = userDefaults else { return [WidgetTripDataForApp]() }
            return _loadWidgetTrips(defaults: defaults)
        }
        print("   - Widget Trip-Daten: \(widgetTrips.count)")
        #endif
    }
}

// MARK: - Widget Trip-Datenmodelle (Main App Target)
// Diese Strukturen werden als JSON in UserDefaults gespeichert und
// müssen exakt mit WidgetTripData / WidgetTripLegData im Widget-Target übereinstimmen.

struct WidgetTripDataForApp: Codable, Identifiable {
    let id: String
    let startTime: String
    let endTime: String
    let interchanges: Int
    let startStation: String
    let endStation: String
    let legs: [WidgetTripLegDataForApp]
}

struct WidgetTripLegDataForApp: Codable {
    let legType: String?
    let boardStopName: String?
    let alightStopName: String?
    let departureTime: String?
    let arrivalTime: String?
    let serviceName: String?
    let serviceType: String?
    let destinationLabel: String?
}

