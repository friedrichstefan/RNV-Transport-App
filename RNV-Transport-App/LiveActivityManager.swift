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
@MainActor
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
    private var notificationObservers: [Any] = []

    /// BGTask Identifier – muss auch in Info.plist unter BGTaskSchedulerPermittedIdentifiers stehen
    static let backgroundTaskIdentifier = "com.stefanfriedrich.rnvapp.liveactivity.refresh"

    // MARK: - Private Helper to access LiveActivityState

    /// Wrapper that resolves `LiveActivityState` at the call‑site so that the
    /// compiler never has to look it up at the top level of this file.
    nonisolated private static var activityState: LiveActivityState { LiveActivityState.shared }
    
    // MARK: - Initialization
    
    init(graphQLService: GraphQLService? = nil) {
        self.graphQLService = graphQLService
        #if DEBUG
        print("📱 [INIT] LiveActivityManager initialisiert")
        #endif

        // Auf App-Lifecycle-Events hören für Hintergrund-Updates (Token-Pattern für sicheres deinit)
        let bgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }
        let fgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillEnterForeground()
        }
        notificationObservers = [bgObserver, fgObserver]
    }

    // MARK: - Background Task Registration

    /// Muss einmal beim App-Start aufgerufen werden (z.B. in AppDelegate oder @main)
    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGAppRefreshTask else { return }
            handleBackgroundTask(bgTask)
        }
        #if DEBUG
        print("✅ [BG] Background Task registriert: \(backgroundTaskIdentifier)")
        #endif
    }

    nonisolated private static func handleBackgroundTask(_ task: BGAppRefreshTask) {
        #if DEBUG
        print("🔄 [BG] Background Task ausgeführt")
        #endif

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

    nonisolated static func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        // Frühester Zeitpunkt: in 15 Minuten (iOS-Minimum)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("⏰ [BG] Background Task geplant für ~15 Minuten")
            #endif
        } catch {
            #if DEBUG
            print("❌ [BG] Konnte Background Task nicht planen: \(error)")
            #endif
        }
    }

    /// Führt Phase-Updates für alle aktiven Activities im Hintergrund durch
    nonisolated private static func performBackgroundUpdate() async {
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
                #if DEBUG
                print("✅ [BG] Activity aktualisiert: Phase → \(newPhase)")
                #endif
            }

            // Beende Activity wenn angekommen
            if isArrived {
                // Nach 5 Minuten automatisch beenden
                if let arrivalDate = DateFormattingHelper.shared.parseISO8601(attrs.arrivalTimeISO),
                   now.timeIntervalSince(arrivalDate) > 300 {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    activityState.setTripActive(attrs.tripId, isActive: false)
                    activityState.removeTripDataForWidget(tripId: attrs.tripId)
                    #if DEBUG
                    print("🛑 [BG] Activity beendet (angekommen)")
                    #endif
                }
            }
        }
    }
    
    // MARK: - Live Activity starten
    
    func startActivity(for trip: DetailedTrip, accessToken: String) async {
        #if DEBUG
        print("🔍 [DEBUG] startActivity aufgerufen für Trip: \(trip.id)")
        #endif
        self.accessToken = accessToken
        
        await endAllActivities()
        
        let authInfo = ActivityAuthorizationInfo()
        #if DEBUG
        print("🔍 [DEBUG] Activity Authorization Status: \(authInfo.areActivitiesEnabled)")
        #endif
        
        guard authInfo.areActivitiesEnabled else {
            let error = "Live Activities sind in den Einstellungen deaktiviert"
            #if DEBUG
            print("⚠️ [WARNING] \(error)")
            #endif
            self.lastError = error
            return
        }
        
        guard let firstTimedLeg = trip.legs.first(where: { $0.isTimedLeg }) else {
            let error = "Keine TimedLeg gefunden"
            #if DEBUG
            print("⚠️ [WARNING] \(error)")
            #endif
            self.lastError = error
            return
        }
        
        guard let boardStop = firstTimedLeg.boardStopName,
              let serviceName = firstTimedLeg.serviceName,
              let serviceType = firstTimedLeg.serviceType,
              let destination = firstTimedLeg.destinationLabel else {
            let error = "Unvollständige Trip-Daten"
            #if DEBUG
            print("⚠️ [WARNING] \(error)")
            #endif
            self.lastError = error
            return
        }
        
        let lastTimedLeg = trip.legs.last { $0.isTimedLeg }
        
        // ⚠️ WICHTIG: Verwende trip.startTime / trip.endTime als Gesamtzeiten,
        // damit die Live Activity die gleichen Zeiten zeigt wie die TripCard.
        // firstTimedLeg.departureTime kann abweichen wenn der Trip mit Fußweg startet.
        let tripDepartureISO = trip.startTime
        let tripArrivalISO = trip.endTime
        
        // Für den initialen State verwende die erste TimedLeg-Abfahrt (für Delay-Berechnung)
        let firstLegDepartureTime = firstTimedLeg.departureTime ?? trip.startTime
        
        let startStation = boardStop
        let endStation = lastTimedLeg?.alightStopName ?? trip.legs.last?.alightStopName ?? "Ziel"
        
        #if DEBUG
        print("📋 [DEBUG] Trip-Zeiten:")
        print("   trip.startTime:              \(trip.startTime)")
        print("   trip.endTime:                \(trip.endTime)")
        print("   firstTimedLeg.departureTime: \(firstTimedLeg.departureTime ?? "nil")")
        print("   lastTimedLeg.arrivalTime:    \(lastTimedLeg?.arrivalTime ?? "nil")")
        print("   → departureTimeISO (Activity): \(tripDepartureISO)")
        print("   → arrivalTimeISO (Activity):   \(tripArrivalISO)")
        #endif
        
        let attributes = TripLiveActivityAttributes(
            tripId: trip.id.uuidString,
            startStation: startStation,
            endStation: endStation,
            totalLegs: trip.legs.filter { $0.isTimedLeg }.count,
            departureTimeISO: tripDepartureISO,
            arrivalTimeISO: tripArrivalISO
        )
        
        let initialDelay = formatter.calculateDelay(
            timetabled: firstLegDepartureTime,
            estimated: firstTimedLeg.estimatedDepartureTime
        )
        
        let initialState = TripLiveActivityAttributes.ContentState(
            currentLegIndex: 0,
            nextStopName: boardStop,
            nextStopTime: formatter.formatTime(firstLegDepartureTime),
            estimatedTime: firstTimedLeg.estimatedDepartureTime.map { formatter.formatTime($0) },
            delay: initialDelay,
            destination: destination,
            lineName: serviceName,
            serviceType: serviceType,
            phase: .beforeDeparture
        )

        let now = Date()
        let staleDate = Self.calculateNextStaleDate(
            departureTimeISO: tripDepartureISO,
            arrivalTimeISO: tripArrivalISO,
            delay: initialDelay,
            currentTime: now
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: staleDate),
                pushType: nil
            )
            
            #if DEBUG
            print("✅ [SUCCESS] Activity erfolgreich erstellt!")
            print("  - Activity ID: \(activity.id)")
            print("  - Departure: \(tripDepartureISO)")
            print("  - Arrival: \(tripArrivalISO)")
            print("  - Stale Date: \(staleDate?.description ?? "nil")")
            #endif
            
            self.activeActivities[trip.id.uuidString] = activity
            self.activeTrips[trip.id.uuidString] = trip
            self.lastError = nil

            // Widget-Daten in UserDefaults speichern
            let widgetData = Self.convertTripToWidgetData(trip)
            Self.activityState.saveTripDataForWidget(widgetData)
            
            await startAutoUpdates(for: trip)

            // Background Task planen für Updates wenn App nicht aktiv ist
            Self.scheduleBackgroundTask()
            
        } catch let error as NSError {
            let errorMsg = "Fehler beim Starten: \(error.localizedDescription) (Code: \(error.code))"
            #if DEBUG
            print("❌ [ERROR] \(errorMsg)")
            #endif
            self.lastError = errorMsg
        } catch {
            let errorMsg = "Unbekannter Fehler: \(error)"
            #if DEBUG
            print("❌ [ERROR] \(errorMsg)")
            #endif
            self.lastError = errorMsg
        }
    }

    // MARK: - Stale Date Berechnung

    /// Berechnet den nächsten Zeitpunkt, an dem iOS die Activity neu rendern soll.
    /// Das ist der Schlüssel: staleDate sorgt dafür, dass iOS die Activity genau
    /// zum Zeitpunkt des Phasenwechsels aktualisiert.
    nonisolated static func calculateNextStaleDate(
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
    
    private func startAutoUpdates(for trip: DetailedTrip) {
        let tripId = trip.id.uuidString

        #if DEBUG
        print("⏰ [DEBUG] Starte Auto-Update für Trip: \(String(tripId.prefix(8)))")
        #endif

        updateTimers[tripId]?.invalidate()
        updateTimers.removeValue(forKey: tripId)

        let startTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAndUpdateLiveActivity(trip: trip)
            }
        }
        RunLoop.main.add(startTimer, forMode: .common)
        updateTimers[tripId] = startTimer
    }
    
    private func fetchAndUpdateLiveActivity(trip: DetailedTrip) async {
        guard let activity = activeActivities[trip.id.uuidString] else {
            return
        }
        
        let activityState = await activity.activityState
        guard activityState != .dismissed && activityState != .ended else {
            updateTimers[trip.id.uuidString]?.invalidate()
            updateTimers.removeValue(forKey: trip.id.uuidString)
            return
        }
        
        let now = Date()
        
        // Verwende die Trip-Zeiten (nicht die Leg-Zeiten) für Phase-Bestimmung
        let departureISO = trip.startTime
        let arrivalISO = trip.endTime

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

        // Widget-Daten aktualisieren, damit Home-Screen-Widgets den neuesten Stand zeigen
        let widgetData = Self.convertTripToWidgetData(trip)
        Self.activityState.saveTripDataForWidget(widgetData)

        // Timer-Intervall für den nächsten Update
        let nextInterval = getUpdateInterval(
            departureTimeISO: departureISO,
            arrivalTimeISO: arrivalISO,
            currentTime: now
        )
        
        let tripId = trip.id.uuidString
        updateTimers[tripId]?.invalidate()
        
        let nextTimer = Timer.scheduledTimer(withTimeInterval: nextInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAndUpdateLiveActivity(trip: trip)
            }
        }
        RunLoop.main.add(nextTimer, forMode: .common)
        updateTimers[tripId] = nextTimer
        
        #if DEBUG
        print("⏰ [UPDATE] Phase: \(currentPhase) | Nächster Update in \(Int(nextInterval))s | Stale: \(staleDate?.description ?? "nil")")
        #endif
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

    private func handleDidEnterBackground() {
        #if DEBUG
        print("📱 [LIFECYCLE] App geht in den Hintergrund")
        #endif

        // Sofort ein letztes Update mit korrektem staleDate machen
        Task {
            for (_, trip) in activeTrips {
                await fetchAndUpdateLiveActivity(trip: trip)
            }
        }

        // Background Task planen
        Self.scheduleBackgroundTask()
    }

    private func handleWillEnterForeground() {
        #if DEBUG
        print("📱 [LIFECYCLE] App kommt in den Vordergrund")
        #endif

        // Sofort alle Activities aktualisieren
        Task {
            for (_, trip) in activeTrips {
                await fetchAndUpdateLiveActivity(trip: trip)
            }
        }
    }
    
    // MARK: - Live Activity beenden
    
    func endActivity(tripId: String) async {
        #if DEBUG
        print("🛑 [DEBUG] endActivity für Trip: \(String(tripId.prefix(8)))")
        #endif
        
        updateTimers[tripId]?.invalidate()
        updateTimers.removeValue(forKey: tripId)
        activeTrips.removeValue(forKey: tripId)
        
        guard let activity = activeActivities[tripId] else {
            #if DEBUG
            print("⚠️ [WARNING] Keine aktive Live Activity zum Beenden gefunden")
            #endif
            return
        }
        
        await activity.end(nil, dismissalPolicy: .immediate)
        
        self.activeActivities.removeValue(forKey: tripId)
        self.lastError = nil

        // Widget-Daten für diesen Trip entfernen
        Self.activityState.removeTripDataForWidget(tripId: tripId)
        
        #if DEBUG
        print("✅ [SUCCESS] Live Activity beendet")
        #endif
    }
    
    // MARK: - Alle Activities beenden
    
    func endAllActivities() async {
        #if DEBUG
        print("🧹 [DEBUG] Beende alle aktiven Live Activities...")
        #endif
        
        let activityIds = Array(activeActivities.keys)
        
        for tripId in activityIds {
            await endActivity(tripId: tripId)
        }
        
        #if DEBUG
        print("✅ [SUCCESS] Alle Live Activities beendet")
        #endif
    }
    
    // MARK: - Alle Activities beenden UND Toggles zurücksetzen
    
    func endAllActivitiesAndResetToggles() async {
        #if DEBUG
        print("🧹 [DEBUG] Beende alle aktiven Live Activities und setze Toggles zurück...")
        #endif
        
        let activityIds = Array(self.activeActivities.keys)
        
        for tripId in activityIds {
            self.updateTimers[tripId]?.invalidate()
            self.updateTimers.removeValue(forKey: tripId)
            
            if let activity = self.activeActivities[tripId] {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            
            Self.activityState.setTripActive(tripId, isActive: false)
        }
        
        self.activeActivities.removeAll()
        self.activeTrips.removeAll()

        // Alle Widget-Daten entfernen
        Self.activityState.removeAllTripDataForWidget()
        
        #if DEBUG
        print("✅ [SUCCESS] Alle Live Activities beendet und Toggles zurückgesetzt")
        #endif
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

    // MARK: - Widget-Daten Konvertierung

    /// Konvertiert einen DetailedTrip in WidgetTripDataForApp für die Home-Screen-Widgets.
    private static func convertTripToWidgetData(_ trip: DetailedTrip) -> WidgetTripDataForApp {
        let startStation = trip.legs.first(where: { $0.isTimedLeg })?.boardStopName ?? "Start"
        let endStation = trip.legs.last(where: { $0.isTimedLeg })?.alightStopName ?? "Ziel"

        let widgetLegs = trip.legs.map { leg in
            WidgetTripLegDataForApp(
                legType: leg.type.rawValue,
                boardStopName: leg.boardStopName,
                alightStopName: leg.alightStopName,
                departureTime: leg.departureTime,
                arrivalTime: leg.arrivalTime,
                serviceName: leg.serviceName,
                serviceType: leg.serviceType,
                destinationLabel: leg.destinationLabel
            )
        }

        return WidgetTripDataForApp(
            id: trip.id.uuidString,
            startTime: trip.startTime,
            endTime: trip.endTime,
            interchanges: trip.interchanges,
            startStation: startStation,
            endStation: endStation,
            legs: widgetLegs
        )
    }

    // MARK: - Deinit

    deinit {
        // Token-basiertes Entfernen – greift nicht auf self zu, daher sicher in nonisolated deinit
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        #if DEBUG
        print("🗑️ [DEINIT] LiveActivityManager wird freigegeben")
        #endif
    }
}

@available(iOS 16.2, *)
extension ActivityState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .active: return "active"
        case .dismissed: return "dismissed"
        case .ended: return "ended"
        case .stale: return "stale"
        case .pending: return "pending"
        @unknown default: return "unknown"
        }
    }
}
