//
//  EndActivityIntent.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 13.01.26.
//

import Foundation
import AppIntents
import ActivityKit

@available(iOS 16.0, *)
struct EndActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Live Activity beenden"
    static var description: IntentDescription = IntentDescription("Beendet die aktive Verbindungs-Verfolgung")
    
    @Parameter(title: "Trip ID")
    var tripId: String
    
    init() {
        self.tripId = ""
    }
    
    init(tripId: String) {
        self.tripId = tripId
    }
    
    func perform() async throws -> some IntentResult {
        print("🛑 [INTENT] EndActivityIntent aufgerufen für Trip: \(tripId)")
        
        // State in UserDefaults auf inaktiv setzen
        LiveActivityState.shared.setTripActive(tripId, isActive: false)
        
        // Alle aktiven Activities finden und beenden
        let activities = Activity<TripLiveActivityAttributes>.activities
        
        for activity in activities {
            if activity.attributes.tripId == tripId {
                print("✅ [INTENT] Beende Activity: \(activity.id)")
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        
        return .result()
    }
}
