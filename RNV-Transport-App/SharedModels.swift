//
//  SharedModels.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 10.01.26.
//

import Foundation
import ActivityKit

// MARK: - Activity Attributes (Shared zwischen App und Widget)

struct TripLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentLegIndex: Int
        var nextStopName: String
        var nextStopTime: String
        var estimatedTime: String?
        var delay: Int? // Verspätung in Minuten
        var destination: String
        var lineName: String
        var serviceType: String
        var phase: TripPhase  // ✅ NEU: Aktuelle Phase der Reise
    }
    
    var tripId: String
    var startStation: String
    var endStation: String
    var totalLegs: Int
    var departureTimeISO: String
    var arrivalTimeISO: String
}

// ✅ NEU: Trip-Phasen
enum TripPhase: String, Codable, Hashable {
    case beforeDeparture = "beforeDeparture"
    case duringJourney = "duringJourney"
    case arrived = "arrived"
}
