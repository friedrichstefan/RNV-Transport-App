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
    private let formatter = DateFormattingHelper.shared
    
    // MARK: - Initialization
    
    init(graphQLService: GraphQLService? = nil) {
        self.graphQLService = graphQLService
        print("📱 [INIT] LiveActivityManager initialisiert")
    }
    
    // MARK: - Live Activity starten
    
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
        
        guard let firstTimedLeg = trip.legs.first(where: { $0.isTimedLeg }) else {
            let error = "Keine TimedLeg gefunden"
            print("⚠️ [WARNING] \(error)")
            await MainActor.run {
                self.lastError = error
            }
            return
        }
        
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
        
        let lastLeg = trip.legs.last { $0.isTimedLeg }
        let arrivalTime = lastLeg?.arrivalTime ?? trip.endTime
        
        let attributes = TripLiveActivityAttributes(
            tripId: trip.id.uuidString,
            startStation: boardStop,
            endStation: trip.legs.last?.alightStopName ?? "Ziel",
            totalLegs: trip.legs.filter { $0.isTimedLeg }.count,
            departureTimeISO: departureTime,
            arrivalTimeISO: arrivalTime
        )
        
        let initialDelay = formatter.calculateDelay(
            timetabled: departureTime,
            estimated: firstTimedLeg.estimatedDepartureTime
        )
        
        let initialState = TripLiveActivityAttributes.ContentState(
            currentLegIndex: 0,
            nextStopName: boardStop,
            nextStopTime: formatter.formatTime(departureTime),
            estimatedTime: firstTimedLeg.estimatedDepartureTime.map { formatter.formatTime($0) },
            delay: initialDelay,
            destination: destination,
            lineName: serviceName,
            serviceType: serviceType,
            phase: .beforeDeparture
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            
            print("✅ [SUCCESS] Activity erfolgreich erstellt!")
            print("  - Activity ID: \(activity.id)")
            
            await MainActor.run {
                self.activeActivities[trip.id.uuidString] = activity
                self.lastError = nil
            }
            
            await startAutoUpdates(for: trip)
            
        } catch let error as NSError {
            let errorMsg = "Fehler beim Starten: \(error.localizedDescription) (Code: \(error.code))"
            print("❌ [ERROR] \(errorMsg)")
            
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
    
    // MARK: - Automatische Updates mit adaptivem Intervall
    
    private func startAutoUpdates(for trip: DetailedTrip) async {
        let tripId = trip.id.uuidString

        print("⏰ [DEBUG] Starte Auto-Update für Trip: \(String(tripId.prefix(8)))")

        // Timer muss auf Main RunLoop erstellt werden, damit er korrekt feuert
        await MainActor.run {
            updateTimers[tripId]?.invalidate()
            updateTimers.removeValue(forKey: tripId)

            let startTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                Task {
                    await self?.fetchAndUpdateLiveActivity(trip: trip)
                }
            }
            RunLoop.main.add(startTimer, forMode: .common)
            updateTimers[tripId] = startTimer
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
        
        // ✅ WICHTIG: Aktuelle Phase erkennen
        let now = Date()
        let isBeforeDeparture = formatter.isBeforeDeparture(trip.legs.first(where: { $0.isTimedLeg })?.departureTime ?? trip.startTime, at: now)
        let isArrived = formatter.isArrived(trip.legs.last(where: { $0.isTimedLeg })?.arrivalTime ?? trip.endTime, at: now)
        
        let currentPhase: TripPhase = isArrived ? .arrived : (isBeforeDeparture ? .beforeDeparture : .duringJourney)
        
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
        
        let delay = formatter.calculateDelay(
            timetabled: departureTime,
            estimated: currentLeg.estimatedDepartureTime
        )
        
        let newState = TripLiveActivityAttributes.ContentState(
            currentLegIndex: currentLegIndex,
            nextStopName: boardStop,
            nextStopTime: formatter.formatTime(departureTime),
            estimatedTime: currentLeg.estimatedDepartureTime.map { formatter.formatTime($0) },
            delay: delay,
            destination: destination,
            lineName: serviceName,
            serviceType: serviceType,
            phase: currentPhase
        )
        
        // ✅ STATE AKTUALISIEREN!
        await activity.update(
            ActivityContent(state: newState, staleDate: nil)
        )
        
        // ✅ Nächster Update mit adaptivem Intervall
        let nextInterval = getUpdateInterval(
            departureTimeISO: trip.legs.first(where: { $0.isTimedLeg })?.departureTime ?? trip.startTime,
            arrivalTimeISO: trip.legs.last(where: { $0.isTimedLeg })?.arrivalTime ?? trip.endTime,
            currentTime: now
        )
        
        let tripId = trip.id.uuidString
        await MainActor.run {
            updateTimers[tripId]?.invalidate()
            
            let nextTimer = Timer.scheduledTimer(withTimeInterval: nextInterval, repeats: false) { [weak self] _ in
                Task {
                    await self?.fetchAndUpdateLiveActivity(trip: trip)
                }
            }
            
            updateTimers[tripId] = nextTimer
            
            print("⏰ [UPDATE] Nächster Update in \(Int(nextInterval))s für Phase: \(currentPhase)")
        }
    }
    
    private func getCurrentLeg(for trip: DetailedTrip) -> TripLeg? {
        let now = Date()
        
        for leg in trip.legs where leg.isTimedLeg {
            if let departureTimeString = leg.departureTime,
               let departureDate = formatter.parseISO8601(departureTimeString) {
                
                if departureDate > now {
                    return leg
                }
            }
        }
        
        return trip.legs.last { $0.isTimedLeg }
    }
    
    // MARK: - Live Activity beenden
    
    func endActivity(tripId: String) async {
        print("🛑 [DEBUG] endActivity für Trip: \(String(tripId.prefix(8)))")
        
        await MainActor.run {
            updateTimers[tripId]?.invalidate()
            updateTimers.removeValue(forKey: tripId)
            print("⏰ [DEBUG] Timer gestoppt für Trip: \(String(tripId.prefix(8)))")
        }
        
        guard let activity = await MainActor.run(body: { activeActivities[tripId] }) else {
            print("⚠️ [WARNING] Keine aktive Live Activity zum Beenden gefunden")
            return
        }
        
        // ✅ RICHTIG
        await activity.end(nil, dismissalPolicy: .immediate)
        
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
                // ✅ RICHTIG
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            
            // State zurücksetzen
            LiveActivityState.shared.setTripActive(tripId, isActive: false)
        }
        
        // Dictionary leeren
        await MainActor.run {
            self.activeActivities.removeAll()
        }
        
        print("✅ [SUCCESS] Alle Live Activities beendet und Toggles zurückgesetzt")
    }
    
    // MARK: - Adaptives Update-Intervall

    private func getUpdateInterval(
        departureTimeISO: String,
        arrivalTimeISO: String,
        currentTime: Date = Date()
    ) -> TimeInterval {
        guard let departureDate = formatter.parseISO8601(departureTimeISO),
              let arrivalDate = formatter.parseISO8601(arrivalTimeISO) else {
            return 30 // Default
        }

        let timeUntilDeparture = departureDate.timeIntervalSince(currentTime)
        let timeUntilArrival = arrivalDate.timeIntervalSince(currentTime)

        if timeUntilDeparture > 0 {
            // Vor Abfahrt: Je näher desto häufiger
            if timeUntilDeparture > 600 { return 60 }
            else if timeUntilDeparture > 300 { return 30 }
            else { return 15 }
        } else if timeUntilArrival > 0 {
            // Während der Fahrt: Je näher desto häufiger
            if timeUntilArrival > 600 { return 30 }
            else { return 15 }
        }

        return 60 // Nach Ankunft selten
    }

    // MARK: - Deinit

    deinit {
        print("🗑️ [DEINIT] LiveActivityManager wird freigegeben")

        // Timer muss vom selben Thread (Main) invalidiert werden, auf dem er erstellt wurde
        let timersToStop = updateTimers
        let block = {
            for (tripId, timer) in timersToStop {
                timer.invalidate()
                print("⏰ [CLEANUP] Timer gestoppt für Trip: \(String(tripId.prefix(8)))")
            }
        }

        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
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
