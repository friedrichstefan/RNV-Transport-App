//
//  LiveActivityState.swift.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 13.01.26.
//

import Foundation

class LiveActivityState {
    static let shared = LiveActivityState()
    
    // ⚠️ WICHTIG: App Group ID anpassen!
    private let appGroupID = "group.com.yourcompany.rnvapp"
    private let activeTripsKey = "activeTrips"
    
    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
    
    func setTripActive(_ tripId: String, isActive: Bool) {
        guard let defaults = userDefaults else {
            print("❌ [STATE] UserDefaults konnte nicht geladen werden")
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
        
        print("✅ [STATE] Trip \(tripId) ist jetzt \(isActive ? "aktiv" : "inaktiv")")
    }
    
    func isTripActive(_ tripId: String) -> Bool {
        let activeTrips = getActiveTrips()
        return activeTrips.contains(tripId)
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
        guard let defaults = userDefaults else { return [] }
        return defaults.stringArray(forKey: activeTripsKey) ?? []
    }
}
