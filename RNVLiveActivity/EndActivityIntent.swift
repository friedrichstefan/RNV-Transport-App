//
//  EndActivityIntent.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 13.01.26.
//

import Foundation
import AppIntents
import ActivityKit

@available(iOS 16.2, *)
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
        #if DEBUG
        print("🛑 [INTENT] EndActivityIntent aufgerufen für Trip: \(String(tripId.prefix(8)))")
        #endif
        
        LiveActivityState.shared.setTripActive(tripId, isActive: false)
        LiveActivityState.shared.removeTripDataForWidget(tripId: tripId)
        
        let activities = Activity<TripLiveActivityAttributes>.activities
        
        for activity in activities {
            if activity.attributes.tripId == tripId {
                #if DEBUG
                print("✅ [INTENT] Beende Activity: \(activity.id)")
                #endif
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        
        return .result()
    }
}
