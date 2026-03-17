//
//  TripDataManager.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import Foundation

class TripDataManager {
    static let shared = TripDataManager()
    
    private let tripDataKey = "savedTripData"
    private let appGroupID = AppConfiguration.appGroupID  // ✅ ZENTRAL
    
    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
    
    // MARK: - Trip speichern
    
    func saveTripData(_ trip: DetailedTrip) {
        guard let defaults = userDefaults else {
            print("❌ [TRIPDATA] UserDefaults konnte nicht geladen werden")
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
                        destinationLabel: leg.destinationLabel
                    )
                }
            )
            
            var savedTrips = getSavedTrips()
            savedTrips.removeAll { $0.id == tripData.id }
            savedTrips.append(tripData)
            
            let allEncoded = try encoder.encode(savedTrips)
            defaults.set(allEncoded, forKey: tripDataKey)
            defaults.synchronize()
            
            print("✅ [TRIPDATA] Trip gespeichert: \(String(trip.id.uuidString.prefix(8)))")
            
        } catch {
            print("❌ [TRIPDATA] Fehler beim Speichern: \(error)")
        }
    }
    
    // MARK: - Trip laden
    
    func getTripData(for tripId: String) -> TripData? {
        let savedTrips = getSavedTrips()
        return savedTrips.first { $0.id == tripId }
    }
    
    // MARK: - Trip löschen
    
    func removeTripData(for tripId: String) {
        guard let defaults = userDefaults else { return }
        
        var savedTrips = getSavedTrips()
        savedTrips.removeAll { $0.id == tripId }
        
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(savedTrips)
            defaults.set(encoded, forKey: tripDataKey)
            defaults.synchronize()
            
            print("✅ [TRIPDATA] Trip entfernt: \(String(tripId.prefix(8)))")
        } catch {
            print("❌ [TRIPDATA] Fehler beim Entfernen: \(error)")
        }
    }
    
    // MARK: - Alle gespeicherten Trips
    
    private func getSavedTrips() -> [TripData] {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: tripDataKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([TripData].self, from: data)
        } catch {
            print("❌ [TRIPDATA] Fehler beim Laden: \(error)")
            return []
        }
    }
    
    // ✅ NEU: Cleanup alte Daten
    func removeExpiredTrips() {
        let now = Date()
        let formatter = DateFormattingHelper.shared
        
        var savedTrips = getSavedTrips()
        let initialCount = savedTrips.count
        
        savedTrips.removeAll { trip in
            guard let arrivalDate = formatter.parseISO8601(trip.endTime) else { return false }
            return now.timeIntervalSince(arrivalDate) > 86400 // 24 Stunden
        }
        
        if savedTrips.count < initialCount {
            do {
                let encoder = JSONEncoder()
                let encoded = try encoder.encode(savedTrips)
                userDefaults?.set(encoded, forKey: tripDataKey)
                userDefaults?.synchronize()
                print("✅ [TRIPDATA] \(initialCount - savedTrips.count) abgelaufene Trips entfernt")
            } catch {
                print("❌ [TRIPDATA] Fehler beim Cleanup: \(error)")
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
}
