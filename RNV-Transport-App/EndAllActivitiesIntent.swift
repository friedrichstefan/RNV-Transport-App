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
        #if DEBUG
        print("🛑 [INTENT] EndAllActivitiesIntent aufgerufen")
        #endif
        
        let activeTrips = LiveActivityState.shared.getAllActiveTrips()
        
        LiveActivityState.shared.deactivateAllTrips()
        LiveActivityState.shared.removeAllTripDataForWidget()
        
        let activities = Activity<TripLiveActivityAttributes>.activities
        
        for activity in activities {
            #if DEBUG
            print("✅ [INTENT] Beende Activity: \(activity.id)")
            #endif
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        
        #if DEBUG
        print("✅ [INTENT] Alle \(activeTrips.count) Activities beendet")
        #endif
        
        return .result()
    }
}
