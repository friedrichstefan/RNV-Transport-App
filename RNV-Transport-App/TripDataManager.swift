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
    private let appGroupID = "group.com.yourcompany.rnvapp" // Gleiche ID wie LiveActivityState
    
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
                        serviceName: leg.serviceName,
                        serviceType: leg.serviceType,
                        destinationLabel: leg.destinationLabel
                    )
                }
            )
            
            let encoded = try encoder.encode(tripData)
            
            var savedTrips = getSavedTrips()
            // Ersetze existierenden Trip oder füge neuen hinzu
            savedTrips.removeAll { $0.id == tripData.id }
            savedTrips.append(tripData)
            
            let allEncoded = try encoder.encode(savedTrips)
            defaults.set(allEncoded, forKey: tripDataKey)
            defaults.synchronize()
            
            print("✅ [TRIPDATA] Trip gespeichert: \(trip.id)")
            
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
            
            print("✅ [TRIPDATA] Trip entfernt: \(tripId)")
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
    let serviceName: String?
    let serviceType: String?
    let destinationLabel: String?
}
