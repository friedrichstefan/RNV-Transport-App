//
//  TripDataManager.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import Foundation
import WidgetKit

class TripDataManager {
    static let shared = TripDataManager()
    
    // WICHTIG: Anderer Key als LiveActivityState.savedTripDataKey ("savedTripData"),
    // um Datenkollisionen im gemeinsamen App-Group-UserDefaults zu vermeiden.
    private let tripDataKey = "plannedTripData"
    private let archivedTripsKey = "archivedTripData"
    private let appGroupID = AppConfiguration.appGroupID

    /// Gecachte UserDefaults-Instanz (thread-safe, sofort initialisiert)
    private let userDefaults: UserDefaults?

    /// Serial Queue für Thread-sichere Lese-/Schreiboperationen
    private let queue = DispatchQueue(label: "com.stefanfriedrich.rnvapp.tripdata")

    /// In-Memory-Cache – vermeidet wiederholtes Decode bei jedem Zugriff
    private var cachedTrips: [TripData]?
    private var cachedArchivedTrips: [ArchivedTripData]?

    /// Debounce-WorkItem für Widget-Reloads
    private var widgetReloadWorkItem: DispatchWorkItem?

    static let archivedTripsDidChangeNotification = Notification.Name("TripDataManagerArchivedTripsDidChange")
    
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
            print("🔄 [WIDGET] Alle Widget-Timelines neu geladen")
            #endif
        }
        widgetReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    // MARK: - Trip speichern
    
    func saveTripData(_ trip: DetailedTrip) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let defaults = self.userDefaults else {
                #if DEBUG
                print("❌ [TRIPDATA] UserDefaults konnte nicht geladen werden")
                #endif
                return
            }
            
            do {
                let encoder = JSONEncoder()
                let tripData = TripData(
                    id: trip.id.uuidString,
                    startTime: trip.startTime,
                    endTime: trip.endTime,
                    interchanges: trip.interchanges,
                    startStation: trip.legs.first?.boardStopName ?? "",
                    endStation: trip.legs.last?.alightStopName ?? "",
                    legs: trip.legs.map { leg in
                        TripLegData(
                            legType: leg.type.rawValue,
                            boardStopName: leg.boardStopName,
                            alightStopName: leg.alightStopName,
                            departureTime: leg.departureTime,
                            arrivalTime: leg.arrivalTime,
                            serviceName: leg.serviceName,
                            serviceType: leg.serviceType,
                            destinationLabel: leg.destinationLabel,
                            intermediateStopNames: leg.intermediateStops.isEmpty ? nil : leg.intermediateStops.map { $0.name }
                        )
                    }
                )
                
                var savedTrips = self.loadCachedTrips(defaults: defaults)
                savedTrips.removeAll { $0.id == tripData.id }
                savedTrips.append(tripData)
                
                let allEncoded = try encoder.encode(savedTrips)
                defaults.set(allEncoded, forKey: self.tripDataKey)
                self.cachedTrips = savedTrips
                
                #if DEBUG
                print("✅ [TRIPDATA] Trip gespeichert: \(String(trip.id.uuidString.prefix(8)))")
                #endif
                
            } catch {
                #if DEBUG
                print("❌ [TRIPDATA] Fehler beim Speichern: \(error)")
                #endif
            }
            
            self.scheduleWidgetReload()
        }
    }
    
    // MARK: - Trip laden
    
    func getTripData(for tripId: String) -> TripData? {
        return queue.sync {
            let savedTrips = self.loadCachedTrips(defaults: userDefaults)
            return savedTrips.first { $0.id == tripId }
        }
    }
    
    // MARK: - Trip löschen
    
    func removeTripData(for tripId: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let defaults = self.userDefaults else { return }
            
            var savedTrips = self.loadCachedTrips(defaults: defaults)
            savedTrips.removeAll { $0.id == tripId }
            
            do {
                let encoder = JSONEncoder()
                let encoded = try encoder.encode(savedTrips)
                defaults.set(encoded, forKey: self.tripDataKey)
                self.cachedTrips = savedTrips
                
                #if DEBUG
                print("✅ [TRIPDATA] Trip entfernt: \(String(tripId.prefix(8)))")
                #endif
                
            } catch {
                #if DEBUG
                print("❌ [TRIPDATA] Fehler beim Entfernen: \(error)")
                #endif
            }
            
            self.scheduleWidgetReload()
        }
    }
    
    // MARK: - Interne Hilfsfunktionen
    
    /// Lädt Trips aus dem Cache oder bei Cache-Miss aus UserDefaults.
    /// Muss innerhalb der `queue` aufgerufen werden.
    private func loadCachedTrips(defaults: UserDefaults?) -> [TripData] {
        if let cached = cachedTrips {
            return cached
        }
        let trips = decodeTripsFromDefaults(defaults: defaults)
        cachedTrips = trips
        return trips
    }
    
    /// Decodiert Trips direkt aus UserDefaults (ohne Cache).
    private func decodeTripsFromDefaults(defaults: UserDefaults?) -> [TripData] {
        guard let defaults = defaults,
              let data = defaults.data(forKey: tripDataKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([TripData].self, from: data)
        } catch {
            #if DEBUG
            print("❌ [TRIPDATA] Fehler beim Laden: \(error)")
            #endif
            return []
        }
    }
    
    // MARK: - Archiv

    func archiveAndRemoveTripData(for tripId: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let defaults = self.userDefaults else { return }

            var savedTrips = self.loadCachedTrips(defaults: defaults)
            guard let tripData = savedTrips.first(where: { $0.id == tripId }) else { return }

            let archived = ArchivedTripData(
                id: tripData.id,
                startTime: tripData.startTime,
                endTime: tripData.endTime,
                startStation: tripData.startStation,
                endStation: tripData.endStation,
                interchanges: tripData.interchanges,
                legs: tripData.legs,
                archivedAt: Date()
            )

            var archivedTrips = self.loadCachedArchivedTrips(defaults: defaults)
            archivedTrips.removeAll { $0.id == tripId }
            archivedTrips.insert(archived, at: 0)
            if archivedTrips.count > 50 {
                archivedTrips = Array(archivedTrips.prefix(50))
            }

            savedTrips.removeAll { $0.id == tripId }

            do {
                let encoder = JSONEncoder()
                defaults.set(try encoder.encode(archivedTrips), forKey: self.archivedTripsKey)
                defaults.set(try encoder.encode(savedTrips), forKey: self.tripDataKey)
                self.cachedArchivedTrips = archivedTrips
                self.cachedTrips = savedTrips
                #if DEBUG
                print("✅ [ARCHIVE] Trip archiviert: \(String(tripId.prefix(8)))")
                #endif
            } catch {
                #if DEBUG
                print("❌ [ARCHIVE] Fehler: \(error)")
                #endif
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.archivedTripsDidChangeNotification, object: nil)
            }
            self.scheduleWidgetReload()
        }
    }

    func getArchivedTrips() -> [ArchivedTripData] {
        return queue.sync {
            guard let defaults = userDefaults else { return [] }
            return loadCachedArchivedTrips(defaults: defaults)
        }
    }

    func clearArchivedTrips() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.userDefaults?.removeObject(forKey: self.archivedTripsKey)
            self.cachedArchivedTrips = nil
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.archivedTripsDidChangeNotification, object: nil)
            }
        }
    }

    private func loadCachedArchivedTrips(defaults: UserDefaults) -> [ArchivedTripData] {
        if let cached = cachedArchivedTrips { return cached }
        guard let data = defaults.data(forKey: archivedTripsKey) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([ArchivedTripData].self, from: data)
            cachedArchivedTrips = decoded
            return decoded
        } catch {
            #if DEBUG
            print("❌ [ARCHIVE] Fehler beim Laden: \(error)")
            #endif
            return []
        }
    }

    func removeExpiredTrips() {        queue.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let formatter = DateFormattingHelper.shared
            
            guard let defaults = self.userDefaults else { return }
            var savedTrips = self.loadCachedTrips(defaults: defaults)
            let initialCount = savedTrips.count
            
            savedTrips.removeAll { trip in
                guard let arrivalDate = formatter.parseISO8601(trip.endTime) else { return false }
                return now.timeIntervalSince(arrivalDate) > 86400 // 24 Stunden
            }
            
            if savedTrips.count < initialCount {
                do {
                    let encoder = JSONEncoder()
                    let encoded = try encoder.encode(savedTrips)
                    defaults.set(encoded, forKey: self.tripDataKey)
                    self.cachedTrips = savedTrips
                    #if DEBUG
                    print("✅ [TRIPDATA] \(initialCount - savedTrips.count) abgelaufene Trips entfernt")
                    #endif
                    
                    self.scheduleWidgetReload()
                } catch {
                    #if DEBUG
                    print("❌ [TRIPDATA] Fehler beim Cleanup: \(error)")
                    #endif
                }
            }
        }
    }
}

// MARK: - Trip Data Models

struct TripData: Codable {
    let id: String
    let startTime: String
    let endTime: String
    let interchanges: Int
    let startStation: String
    let endStation: String
    let legs: [TripLegData]
}

struct TripLegData: Codable {
    let legType: String?
    let boardStopName: String?
    let alightStopName: String?
    let departureTime: String?
    let arrivalTime: String?
    let serviceName: String?
    let serviceType: String?
    let destinationLabel: String?
    let intermediateStopNames: [String]?
}

// MARK: - Archived Trip Model

struct ArchivedTripData: Codable, Identifiable {
    let id: String
    let startTime: String
    let endTime: String
    let startStation: String
    let endStation: String
    let interchanges: Int
    let legs: [TripLegData]
    let archivedAt: Date
}