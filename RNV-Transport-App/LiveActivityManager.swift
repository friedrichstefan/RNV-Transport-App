//
//  LiveActivityManager.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 10.01.26.
//

import Foundation
import ActivityKit
import Combine
import BackgroundTasks
import UIKit

@available(iOS 16.2, *)
class LiveActivityManager: ObservableObject {
    // MARK: - Published Properties
    
    @Published var activeActivities: [String: Activity<TripLiveActivityAttributes>] = [:]
    @Published var lastError: String?
    
    // MARK: - Private Properties
    
    private var updateTimers: [String: Timer] = [:]
    private var activeTrips: [String: DetailedTrip] = [:]
    private var graphQLService: GraphQLService?
    private var accessToken: String = ""
    private let formatter = DateFormattingHelper.shared

    /// BGTask Identifier – muss auch in Info.plist unter BGTaskSchedulerPermittedIdentifiers stehen
    static let backgroundTaskIdentifier = "com.stefanfriedrich.rnvapp.liveactivity.refresh"

    // MARK: - Private Helper to access LiveActivityState

    /// Wrapper that resolves `LiveActivityState` at the call‑site so that the
    /// compiler never has to look it up at the top level of this file.
    private static var activityState: LiveActivityState { LiveActivityState.shared }
    
    // MARK: - Initialization
    
    init(graphQLService: GraphQLService? = nil) {
        self.graphQLService = graphQLService
        print("📱 [INIT] LiveActivityManager initialisiert")

        // Auf App-Lifecycle-Events hören für Hintergrund-Updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    // MARK: - Background Task Registration

    /// Muss einmal beim App-Start aufgerufen werden (z.B. in AppDelegate oder @main)
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGAppRefreshTask else { return }
            handleBackgroundTask(bgTask)
        }
        print("✅ [BG] Background Task registriert: \(backgroundTaskIdentifier)")
    }

    private static func handleBackgroundTask(_ task: BGAppRefreshTask) {
        print("🔄 [BG] Background Task ausgeführt")

        // Nächsten Background Task planen
        scheduleBackgroundTask()

        let updateTask = Task {
            await performBackgroundUpdate()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            updateTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    static func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        // Frühester Zeitpunkt: in 15 Minuten (iOS-Minimum)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("⏰ [BG] Background Task geplant für ~15 Minuten")
        } catch {
            print("❌ [BG] Konnte Background Task nicht planen: \(error)")
        }
    }

    /// Führt Phase-Updates für alle aktiven Activities im Hintergrund durch
    private static func performBackgroundUpdate() async {
        let activeTrips = activityState.getAllActiveTrips()
        guard !activeTrips.isEmpty else { return }

        let now = Date()
        let formatter = DateFormattingHelper.shared

        for activity in Activity<TripLiveActivityAttributes>.activities {
            let attrs = activity.attributes
            let currentState = activity.content.state

            let isBeforeDeparture = formatter.isBeforeDeparture(attrs.departureTimeISO, at: now)
            let isArrived = formatter.isArrived(attrs.arrivalTimeISO, at: now)

            let newPhase: TripPhase = isArrived ? .arrived : (isBeforeDeparture ? .beforeDeparture : .duringJourney)

            // Nur updaten wenn sich die Phase geändert hat
            if newPhase != currentState.phase {
                let newState = TripLiveActivityAttributes.ContentState(
                    currentLegIndex: currentState.currentLegIndex,
                    nextStopName: currentState.nextStopName,
                    nextStopTime: currentState.nextStopTime,
                    estimatedTime: currentState.estimatedTime,
                    delay: currentState.delay,
                    destination: currentState.destination,
                    lineName: currentState.lineName,
                    serviceType: currentState.serviceType,
                    phase: newPhase
                )

                let staleDate = calculateNextStaleDate(
                    departureTimeISO: attrs.departureTimeISO,
                    arrivalTimeISO: attrs.arrivalTimeISO,
                    delay: currentState.delay,
                    currentTime: now
                )

                await activity.update(
                    ActivityContent(state: newState, staleDate: staleDate)
                )
                print("✅ [BG] Activity aktualisiert: Phase → \(newPhase)")
            }

            // Beende Activity wenn angekommen
            if isArrived {
                // Nach 5 Minuten automatisch beenden
                if let arrivalDate = DateFormattingHelper.shared.parseISO8601(attrs.arrivalTimeISO),
                   now.timeIntervalSince(arrivalDate) > 300 {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    activityState.setTripActive(attrs.tripId, isActive: false)
                    print("🛑 [BG] Activity beendet (angekommen)")
                }
            }
        }
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

        let now = Date()
        let staleDate = Self.calculateNextStaleDate(
            departureTimeISO: departureTime,
            arrivalTimeISO: arrivalTime,
            delay: initialDelay,
            currentTime: now
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: staleDate),
                pushType: nil
            )
            
            print("✅ [SUCCESS] Activity erfolgreich erstellt!")
            print("  - Activity ID: \(activity.id)")
            print("  - Stale Date: \(staleDate?.description ?? "nil")")
            
            await MainActor.run {
                self.activeActivities[trip.id.uuidString] = activity
                self.activeTrips[trip.id.uuidString] = trip
                self.lastError = nil
            }
            
            await startAutoUpdates(for: trip)

            // Background Task planen für Updates wenn App nicht aktiv ist
            Self.scheduleBackgroundTask()
            
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

    // MARK: - Stale Date Berechnung

    /// Berechnet den nächsten Zeitpunkt, an dem iOS die Activity neu rendern soll.
    /// Das ist der Schlüssel: staleDate sorgt dafür, dass iOS die Activity genau
    /// zum Zeitpunkt des Phasenwechsels aktualisiert.
    static func calculateNextStaleDate(
        departureTimeISO: String,
        arrivalTimeISO: String,
        delay: Int?,
        currentTime: Date
    ) -> Date? {
        let formatter = DateFormattingHelper.shared

        guard let departureDate = formatter.parseISO8601(departureTimeISO),
              let arrivalDate = formatter.parseISO8601(arrivalTimeISO) else {
            return currentTime.addingTimeInterval(60)
        }

        let effectiveDeparture: Date
        let effectiveArrival: Date

        if let d = delay, d > 0 {
            effectiveDeparture = departureDate.addingTimeInterval(TimeInterval(d * 60))
            effectiveArrival = arrivalDate.addingTimeInterval(TimeInterval(d * 60))
        } else {
            effectiveDeparture = departureDate
            effectiveArrival = arrivalDate
        }

        if currentTime < effectiveDeparture {
            // Vor Abfahrt: Nächstes Update genau bei Abfahrt (Phasenwechsel!)
            return effectiveDeparture
        } else if currentTime < effectiveArrival {
            // Während Fahrt: Nächstes Update bei Ankunft
            return effectiveArrival
        } else {
            // Angekommen: In 5 Minuten beenden
            return currentTime.addingTimeInterval(300)
        }
    }
    
    // MARK: - Automatische Updates mit adaptivem Intervall
    
    private func startAutoUpdates(for trip: DetailedTrip) async {
        let tripId = trip.id.uuidString

        print("⏰ [DEBUG] Starte Auto-Update für Trip: \(String(tripId.prefix(8)))")

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
        
        let now = Date()
        let departureISO = trip.legs.first(where: { $0.isTimedLeg })?.departureTime ?? trip.startTime
        let arrivalISO = trip.legs.last(where: { $0.isTimedLeg })?.arrivalTime ?? trip.endTime

        let isBeforeDeparture = formatter.isBeforeDeparture(departureISO, at: now)
        let isArrived = formatter.isArrived(arrivalISO, at: now)
        
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

        // staleDate = Zeitpunkt des nächsten Phasenwechsels
        let staleDate = Self.calculateNextStaleDate(
            departureTimeISO: departureISO,
            arrivalTimeISO: arrivalISO,
            delay: delay,
            currentTime: now
        )

        await activity.update(
            ActivityContent(state: newState, staleDate: staleDate)
        )

        // Timer-Intervall für den nächsten Update
        let nextInterval = getUpdateInterval(
            departureTimeISO: departureISO,
            arrivalTimeISO: arrivalISO,
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
            RunLoop.main.add(nextTimer, forMode: .common)
            updateTimers[tripId] = nextTimer
            
            print("⏰ [UPDATE] Phase: \(currentPhase) | Nächster Update in \(Int(nextInterval))s | Stale: \(staleDate?.description ?? "nil")")
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

    // MARK: - App Lifecycle

    @objc private func appDidEnterBackground() {
        print("📱 [LIFECYCLE] App geht in den Hintergrund")

        // Sofort ein letztes Update mit korrektem staleDate machen
        Task {
            for (tripId, trip) in activeTrips {
                await fetchAndUpdateLiveActivity(trip: trip)
            }
        }

        // Background Task planen
        Self.scheduleBackgroundTask()
    }

    @objc private func appWillEnterForeground() {
        print("📱 [LIFECYCLE] App kommt in den Vordergrund")

        // Sofort alle Activities aktualisieren
        Task {
            for (tripId, trip) in activeTrips {
                await fetchAndUpdateLiveActivity(trip: trip)
            }
        }
    }
    
    // MARK: - Live Activity beenden
    
    func endActivity(tripId: String) async {
        print("🛑 [DEBUG] endActivity für Trip: \(String(tripId.prefix(8)))")
        
        await MainActor.run {
            updateTimers[tripId]?.invalidate()
            updateTimers.removeValue(forKey: tripId)
            activeTrips.removeValue(forKey: tripId)
            print("⏰ [DEBUG] Timer gestoppt für Trip: \(String(tripId.prefix(8)))")
        }
        
        guard let activity = await MainActor.run(body: { activeActivities[tripId] }) else {
            print("⚠️ [WARNING] Keine aktive Live Activity zum Beenden gefunden")
            return
        }
        
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
            await MainActor.run {
                self.updateTimers[tripId]?.invalidate()
                self.updateTimers.removeValue(forKey: tripId)
            }
            
            if let activity = await MainActor.run(body: { self.activeActivities[tripId] }) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            
            Self.activityState.setTripActive(tripId, isActive: false)
        }
        
        await MainActor.run {
            self.activeActivities.removeAll()
            self.activeTrips.removeAll()
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
            return 30
        }

        let timeUntilDeparture = departureDate.timeIntervalSince(currentTime)
        let timeUntilArrival = arrivalDate.timeIntervalSince(currentTime)

        if timeUntilDeparture > 0 {
            // Vor Abfahrt: Je näher desto häufiger
            if timeUntilDeparture > 600 { return 60 }
            else if timeUntilDeparture > 120 { return 30 }
            else if timeUntilDeparture > 30 { return 10 }
            // Ganz kurz vor Abfahrt: genau zur Abfahrt updaten
            else { return max(1, timeUntilDeparture) }
        } else if timeUntilArrival > 0 {
            // Während der Fahrt
            if timeUntilArrival > 600 { return 30 }
            else if timeUntilArrival > 120 { return 15 }
            // Kurz vor Ankunft: genau zur Ankunft updaten
            else { return max(1, timeUntilArrival) }
        }

        return 60
    }

    // MARK: - Deinit

    deinit {
        print("🗑️ [DEINIT] LiveActivityManager wird freigegeben")

        NotificationCenter.default.removeObserver(self)

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
