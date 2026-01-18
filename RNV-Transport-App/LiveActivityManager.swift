//
//  LiveActivityManager.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 10.01.26.
//

import Foundation
import ActivityKit
import Combine

@available(iOS 16.2, *)
class LiveActivityManager: ObservableObject {
    // MARK: - Published Properties
    
    @Published var activeActivities: [String: Activity<TripLiveActivityAttributes>] = [:]
    @Published var lastError: String?
    
    // MARK: - Private Properties
    
    private var updateTimers: [String: Timer] = [:]
    private var graphQLService: GraphQLService?
    private var accessToken: String = ""
    
    // MARK: - Initialization
    
    init(graphQLService: GraphQLService? = nil) {
        self.graphQLService = graphQLService
        print("📱 [INIT] LiveActivityManager initialisiert")
    }
    
    // MARK: - Live Activity starten mit Auto-Updates
    
    func startActivity(for trip: DetailedTrip, accessToken: String) async {
        print("🔍 [DEBUG] startActivity aufgerufen für Trip: \(trip.id)")
        self.accessToken = accessToken
        
        await endAllActivities()
        
        let authInfo = ActivityAuthorizationInfo()
        print("🔍 [DEBUG] Activity Authorization Status: \(authInfo.areActivitiesEnabled)")
        
        guard authInfo.areActivitiesEnabled else {
            let error = "Live Activities sind in den Einstellungen deaktiviert"
            print("⚠️ [WARNING] \(error)")
            await MainActor.run {
                self.lastError = error
            }
            return
        }
        
        guard let firstTimedLeg = trip.legs.first(where: { $0.type == "TimedLeg" }) else {
            let error = "Keine TimedLeg gefunden"
            print("⚠️ [WARNING] \(error)")
            await MainActor.run {
                self.lastError = error
            }
            return
        }
        
        print("🔍 [DEBUG] Erste TimedLeg gefunden:")
        print("  - boardStopName: \(firstTimedLeg.boardStopName ?? "nil")")
        print("  - departureTime: \(firstTimedLeg.departureTime ?? "nil")")
        print("  - serviceName: \(firstTimedLeg.serviceName ?? "nil")")
        print("  - serviceType: \(firstTimedLeg.serviceType ?? "nil")")
        print("  - destinationLabel: \(firstTimedLeg.destinationLabel ?? "nil")")
        
        guard let boardStop = firstTimedLeg.boardStopName,
              let departureTime = firstTimedLeg.departureTime,
              let serviceName = firstTimedLeg.serviceName,
              let serviceType = firstTimedLeg.serviceType,
              let destination = firstTimedLeg.destinationLabel else {
            let error = "Unvollständige Trip-Daten"
            print("⚠️ [WARNING] \(error)")
            await MainActor.run {
                self.lastError = error
            }
            return
        }
        
        let lastLeg = trip.legs.last { $0.type == "TimedLeg" }
        let arrivalTime = lastLeg?.arrivalTime ?? trip.endTime
        
        print("🔍 [DEBUG] Ankunftszeit: \(arrivalTime)")
        
        let attributes = TripLiveActivityAttributes(
            tripId: trip.id.uuidString,
            startStation: boardStop,
            endStation: trip.legs.last?.alightStopName ?? "Ziel",
            totalLegs: trip.legs.filter { $0.type == "TimedLeg" }.count,
            departureTimeISO: departureTime,
            arrivalTimeISO: arrivalTime
        )
        
        let initialState = TripLiveActivityAttributes.ContentState(
            currentLegIndex: 0,
            nextStopName: boardStop,
            nextStopTime: formatTime(departureTime),
            estimatedTime: firstTimedLeg.estimatedDepartureTime.map { formatTime($0) },
            delay: calculateDelay(
                timetabled: departureTime,
                estimated: firstTimedLeg.estimatedDepartureTime
            ),
            destination: destination,
            lineName: serviceName,
            serviceType: serviceType,
            phase: .beforeDeparture
        )
        
        print("🔍 [DEBUG] Attributes erstellt:")
        print("  - tripId: \(attributes.tripId)")
        print("  - startStation: \(attributes.startStation)")
        print("  - endStation: \(attributes.endStation)")
        print("  - departureTimeISO: \(attributes.departureTimeISO)")
        print("  - arrivalTimeISO: \(attributes.arrivalTimeISO)")
        
        do {
            print("🔄 [DEBUG] Versuche Activity.request...")
            
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            
            print("✅ [SUCCESS] Activity erfolgreich erstellt!")
            print("  - Activity ID: \(activity.id)")
            print("  - Activity State: \(activity.activityState)")
            
            await MainActor.run {
                self.activeActivities[trip.id.uuidString] = activity
                self.lastError = nil
            }
            
            await MainActor.run {
                self.startAutoUpdates(for: trip)
            }
            
            schedulePhaseTransition(for: trip)
            scheduleArrivalTransition(for: trip)
            
        } catch let error as NSError {
            let errorMsg = "Fehler beim Starten: \(error.localizedDescription) (Code: \(error.code))"
            print("❌ [ERROR] \(errorMsg)")
            print("   Domain: \(error.domain)")
            print("   UserInfo: \(error.userInfo)")
            
            await MainActor.run {
                self.lastError = errorMsg
            }
        } catch {
            let errorMsg = "Unbekannter Fehler: \(error)"
            print("❌ [ERROR] \(errorMsg)")
            
            await MainActor.run {
                self.lastError = errorMsg
            }
        }
    }
    
    // MARK: - Automatische Phase-Erkennung
    
    private func schedulePhaseTransition(for trip: DetailedTrip) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let firstTimedLeg = trip.legs.first(where: { $0.type == "TimedLeg" }),
              let departureTime = firstTimedLeg.departureTime,
              let departureDate = formatter.date(from: departureTime) else {
            print("⚠️ [WARNING] Kann Abfahrtszeit nicht parsen")
            return
        }
        
        let now = Date()
        let timeUntilDeparture = departureDate.timeIntervalSince(now)
        
        if timeUntilDeparture > 0 {
            print("⏰ [SCHEDULE] Phase-Übergang zu 'duringJourney' in \(Int(timeUntilDeparture)) Sekunden")
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeUntilDeparture * 1_000_000_000))
                await transitionToDuringJourney(for: trip)
            }
        } else {
            print("ℹ️ [INFO] Fahrt bereits gestartet")
        }
    }
    
    private func transitionToDuringJourney(for trip: DetailedTrip) async {
        print("🔄 [TRANSITION] Wechsle zu 'duringJourney'-Phase")
        
        guard let activity = await MainActor.run(body: { activeActivities[trip.id.uuidString] }) else {
            print("⚠️ [WARNING] Keine aktive Activity gefunden")
            return
        }
        
        guard let currentLeg = getCurrentLeg(for: trip),
              let boardStop = currentLeg.boardStopName,
              let departureTime = currentLeg.departureTime,
              let serviceName = currentLeg.serviceName,
              let serviceType = currentLeg.serviceType,
              let destination = currentLeg.destinationLabel else {
            print("⚠️ [WARNING] Unvollständige Leg-Daten")
            return
        }
        
        let newState = TripLiveActivityAttributes.ContentState(
            currentLegIndex: 1,
            nextStopName: boardStop,
            nextStopTime: formatTime(departureTime),
            estimatedTime: currentLeg.estimatedDepartureTime.map { formatTime($0) },
            delay: calculateDelay(
                timetabled: departureTime,
                estimated: currentLeg.estimatedDepartureTime
            ),
            destination: destination,
            lineName: serviceName,
            serviceType: serviceType,
            phase: .duringJourney
        )
        
    }
    
    // MARK: - Ankunfts-Übergang planen
    
    private func scheduleArrivalTransition(for trip: DetailedTrip) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let lastLeg = trip.legs.last { $0.type == "TimedLeg" }
        let arrivalTime = lastLeg?.arrivalTime ?? trip.endTime
        
        guard let arrivalDate = formatter.date(from: arrivalTime) else {
            print("⚠️ [WARNING] Kann Ankunftszeit nicht parsen")
            return
        }
        
        let now = Date()
        let timeUntilArrival = arrivalDate.timeIntervalSince(now)
        
        if timeUntilArrival > 0 {
            print("⏰ [SCHEDULE] Phase-Übergang zu 'arrived' in \(Int(timeUntilArrival)) Sekunden")
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeUntilArrival * 1_000_000_000))
                await transitionToArrived(for: trip)
            }
        } else {
            print("ℹ️ [INFO] Bereits angekommen")
        }
    }
    
    private func transitionToArrived(for trip: DetailedTrip) async {
        print("🎯 [TRANSITION] Wechsle zu 'arrived'-Phase")
        
        guard let activity = await MainActor.run(body: { activeActivities[trip.id.uuidString] }) else {
            print("⚠️ [WARNING] Keine aktive Activity gefunden")
            return
        }
        
        var currentState = activity.content.state
        currentState.phase = .arrived
        
    }
    
    // MARK: - Automatische Updates
    
    private func startAutoUpdates(for trip: DetailedTrip) {
        let tripId = trip.id.uuidString
        
        updateTimers[tripId]?.invalidate()
        updateTimers.removeValue(forKey: tripId)
        
        print("⏰ [DEBUG] Starte Auto-Update Timer für Trip: \(tripId)")
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchAndUpdateLiveActivity(trip: trip)
            }
        }
        
        RunLoop.main.add(timer, forMode: .common)
        updateTimers[tripId] = timer
        
        print("✅ [SUCCESS] Auto-Update Timer gestartet (1s Intervall)")
        
        Task {
            await fetchAndUpdateLiveActivity(trip: trip)
        }
    }
    
    private func fetchAndUpdateLiveActivity(trip: DetailedTrip) async {
        guard let activity = await MainActor.run(body: { activeActivities[trip.id.uuidString] }) else {
            return
        }
        
        let activityState = await activity.activityState
        guard activityState != .dismissed && activityState != .ended else {
            await MainActor.run {
                updateTimers[trip.id.uuidString]?.invalidate()
                updateTimers.removeValue(forKey: trip.id.uuidString)
            }
            return
        }
        
        let currentPhase = await activity.content.state.phase
        if currentPhase == .arrived {
            return
        }
        
        guard let currentLeg = getCurrentLeg(for: trip),
              let boardStop = currentLeg.boardStopName,
              let departureTime = currentLeg.departureTime,
              let serviceName = currentLeg.serviceName,
              let serviceType = currentLeg.serviceType,
              let destination = currentLeg.destinationLabel else {
            return
        }
        
        let currentLegIndex = trip.legs.firstIndex(where: { leg in
            leg.boardStopName == currentLeg.boardStopName &&
            leg.departureTime == currentLeg.departureTime
        }) ?? 0
        
        let delay = calculateDelay(
            timetabled: departureTime,
            estimated: currentLeg.estimatedDepartureTime
        )
        
        let newState = TripLiveActivityAttributes.ContentState(
            currentLegIndex: currentLegIndex,
            nextStopName: boardStop,
            nextStopTime: formatTime(departureTime),
            estimatedTime: currentLeg.estimatedDepartureTime.map { formatTime($0) },
            delay: delay,
            destination: destination,
            lineName: serviceName,
            serviceType: serviceType,
            phase: currentPhase
        )
        
    }
    
    private func getCurrentLeg(for trip: DetailedTrip) -> TripLeg? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let now = Date()
        
        for leg in trip.legs where leg.type == "TimedLeg" {
            if let departureTimeString = leg.departureTime,
               let departureDate = formatter.date(from: departureTimeString) {
                
                if departureDate > now {
                    return leg
                }
            }
        }
        
        return trip.legs.last { $0.type == "TimedLeg" }
    }
    
    // MARK: - Live Activity beenden
    
    func endActivity(tripId: String) async {
        print("🛑 [DEBUG] endActivity für Trip: \(tripId)")
        
        await MainActor.run {
            updateTimers[tripId]?.invalidate()
            updateTimers.removeValue(forKey: tripId)
            print("⏰ [DEBUG] Timer gestoppt für Trip: \(tripId)")
        }
        
        guard let activity = await MainActor.run(body: { activeActivities[tripId] }) else {
            print("⚠️ [WARNING] Keine aktive Live Activity zum Beenden gefunden")
            return
        }
        
        await activity.end(
            ActivityContent(state: activity.content.state, staleDate: nil),
            dismissalPolicy: .default
        )
        
        await MainActor.run {
            self.activeActivities.removeValue(forKey: tripId)
            self.lastError = nil
        }
        
        print("✅ [SUCCESS] Live Activity beendet")
    }
    
    // MARK: - Alle Activities beenden
    
    func endAllActivities() async {
        print("🧹 [DEBUG] Beende alle aktiven Live Activities...")
        
        let activityIds = await MainActor.run {
            Array(activeActivities.keys)
        }
        
        for tripId in activityIds {
            await endActivity(tripId: tripId)
        }
        
        print("✅ [SUCCESS] Alle Live Activities beendet")
    }
    
    // MARK: - Alle Activities beenden UND Toggles zurücksetzen
    
    func endAllActivitiesAndResetToggles() async {
        print("🧹 [DEBUG] Beende alle aktiven Live Activities und setze Toggles zurück...")
        
        let activityIds = await MainActor.run {
            Array(self.activeActivities.keys)
        }
        
        for tripId in activityIds {
            // Timer stoppen
            await MainActor.run {
                self.updateTimers[tripId]?.invalidate()
                self.updateTimers.removeValue(forKey: tripId)
            }
            
            // Activity beenden
            if let activity = await MainActor.run(body: { self.activeActivities[tripId] }) {
                await activity.end(
                    ActivityContent(state: activity.content.state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
            
            // State in UserDefaults zurücksetzen
            LiveActivityState.shared.setTripActive(tripId, isActive: false)
            
            print("✅ [CLEANUP] Trip \(tripId) beendet und Toggle zurückgesetzt")
        }
        
        // Dictionary leeren
        await MainActor.run {
            self.activeActivities.removeAll()
        }
        
        print("✅ [SUCCESS] Alle Live Activities beendet und alle Toggles zurückgesetzt")
    }
    
    // MARK: - Helper: Zeit formatieren
    
    private func formatTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: isoString) else {
            return isoString
        }
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = .current
        return timeFormatter.string(from: date)
    }
    
    // MARK: - Helper: Verspätung berechnen
    
    private func calculateDelay(timetabled: String, estimated: String?) -> Int? {
        guard let estimatedString = estimated else {
            return nil
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let timetabledDate = formatter.date(from: timetabled),
              let estimatedDate = formatter.date(from: estimatedString) else {
            return nil
        }
        
        let delaySeconds = estimatedDate.timeIntervalSince(timetabledDate)
        let delayMinutes = Int(delaySeconds / 60)
        
        return delayMinutes > 0 ? delayMinutes : nil
    }
    
    // MARK: - Deinit
    
    deinit {
        print("🗑️ [DEINIT] LiveActivityManager wird freigegeben")
        
        for (tripId, timer) in updateTimers {
            timer.invalidate()
            print("⏰ [CLEANUP] Timer gestoppt für Trip: \(tripId)")
        }
        updateTimers.removeAll()
    }
}

@available(iOS 16.2, *)
extension ActivityState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .active: return "active"
        case .dismissed: return "dismissed"
        case .ended: return "ended"
        @unknown default: return "unknown"
        }
    }
}
