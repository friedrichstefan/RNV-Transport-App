//
//  EndAllActivitiesIntent.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 14.01.26.
//

import Foundation
import AppIntents
import ActivityKit

@available(iOS 16.2, *)
struct EndAllActivitiesIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Alle Live Activities beenden"
    static var description: IntentDescription = IntentDescription("Beendet alle aktiven Verbindungs-Verfolgungen")
    
    init() {}
    
    @MainActor
    func perform() async throws -> some IntentResult {
        print("🛑 [INTENT] EndAllActivitiesIntent aufgerufen")
        
        let activeTrips = LiveActivityState.shared.getAllActiveTrips()
        
        LiveActivityState.shared.deactivateAllTrips()
        
        let activities = Activity<TripLiveActivityAttributes>.activities
        
        for activity in activities {
            print("✅ [INTENT] Beende Activity: \(activity.id)")
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        
        print("✅ [INTENT] Alle \(activeTrips.count) Activities beendet")
        
        return .result()
    }
}
