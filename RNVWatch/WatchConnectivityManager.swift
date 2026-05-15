// Kommunikation zwischen Watch und iPhone über WatchConnectivity.
// Die Watch kann Abfahrten für eine Haltestelle beim iPhone anfordern.

import Foundation
import WatchConnectivity
import Combine

// Nachrichtentypen (müssen mit iPhone-Seite übereinstimmen)
enum WatchMessage {
    static let requestDepartures       = "requestDepartures"
    static let stationIDKey            = "stationID"
    static let stationNameKey          = "stationName"
    static let departuresKey           = "departures"
    static let requestConnections      = "requestConnections"
    static let fromIDKey               = "fromID"
    static let toIDKey                 = "toID"
    static let fromNameKey             = "fromName"
    static let toNameKey               = "toName"
    static let connectionsKey          = "connections"
    static let requestStationSearch    = "requestStationSearch"
    static let searchQueryKey          = "searchQuery"
    static let stationSearchResultsKey = "stationSearchResults"
}

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var departures: [WatchDeparture] = []
    @Published var isLoading = false
    @Published var lastError: String? = nil
    @Published var isReachable = false

    @Published var connectionResults: [TripData] = []
    @Published var connectionsLoading = false
    @Published var connectionsError: String? = nil

    @Published var stationSearchResults: [WatchStation] = []
    @Published var stationSearchLoading = false
    @Published var stationSearchError: String? = nil

    @Published var debugLog: [String] = []

    var onContextUpdated: (() -> Void)? = nil

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func log(_ msg: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let entry = "\(f.string(from: Date())) \(msg)"
        print("[WatchDebug] \(entry)")
        debugLog.insert(entry, at: 0)
        if debugLog.count > 80 { debugLog.removeLast() }
    }

    // MARK: - Initiale Daten vom iPhone anfordern

    private var needsInitialData = true

    func requestInitialData() {
        guard WCSession.default.isReachable else {
            needsInitialData = true
            log("requestInitialData: iPhone nicht erreichbar – verzögert")
            return
        }
        needsInitialData = false
        log("requestInitialData: sende Anfrage ans iPhone")
        WCSession.default.sendMessage(["requestTripData": true]) { [weak self] reply in
            Task { @MainActor [weak self] in
                let defaults = UserDefaults(suiteName: "group.com.stefanfriedrich.rnvapp")
                if let tripData = reply["plannedTripData"] as? Data {
                    defaults?.set(tripData, forKey: "plannedTripData")
                }
                if let savedData = reply["savedTripData"] as? Data {
                    defaults?.set(savedData, forKey: "savedTripData")
                }
                self?.log("requestInitialData: Antwort erhalten (geplanteFahrten=\(reply["plannedTripData"] != nil), gespeichert=\(reply["savedTripData"] != nil))")
                self?.onContextUpdated?()
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.log("requestInitialData: Fehler – \(error.localizedDescription)")
                self?.needsInitialData = true
            }
        }
    }

    // MARK: - Abfahrten anfragen

    func requestDepartures(stationID: String, stationName: String) {
        log("requestDepartures: \(stationName) (\(stationID))")
        if WCSession.default.isReachable {
            log("→ Pfad: iPhone (WCSession erreichbar)")
            requestViaiPhone(stationID: stationID, stationName: stationName)
        } else if WatchDirectService.shared.hasCredentials {
            log("→ Pfad: direkte API (Credentials vorhanden)")
            Task { await requestDirectly(stationID: stationID) }
        } else {
            log("→ Pfad: keiner – iPhone nicht erreichbar, keine Credentials")
            lastError = "iPhone nicht erreichbar"
        }
    }

    // MARK: - Stationssuche

    func requestStationSearch(query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            stationSearchResults = []
            return
        }
        guard WCSession.default.isReachable else {
            stationSearchError = "iPhone nicht erreichbar"
            return
        }
        stationSearchLoading = true
        stationSearchError = nil

        let msg: [String: Any] = [
            WatchMessage.requestStationSearch: true,
            WatchMessage.searchQueryKey: query
        ]

        WCSession.default.sendMessage(msg) { [weak self] reply in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stationSearchLoading = false
                if let rawData = reply[WatchMessage.stationSearchResultsKey] as? Data,
                   let decoded = try? JSONDecoder().decode([WatchStation].self, from: rawData) {
                    self.stationSearchResults = decoded
                } else {
                    self.stationSearchResults = []
                }
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stationSearchLoading = false
                self.stationSearchError = error.localizedDescription
            }
        }
    }

    // MARK: - Verbindungen anfragen

    func requestConnections(fromID: String, toID: String, fromName: String, toName: String) {
        guard WCSession.default.isReachable else {
            connectionsError = "iPhone nicht erreichbar"
            return
        }
        connectionsLoading = true
        connectionsError = nil

        let msg: [String: Any] = [
            WatchMessage.requestConnections: true,
            WatchMessage.fromIDKey: fromID,
            WatchMessage.toIDKey: toID,
            WatchMessage.fromNameKey: fromName,
            WatchMessage.toNameKey: toName
        ]

        WCSession.default.sendMessage(msg) { [weak self] reply in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.connectionsLoading = false
                if let rawData = reply[WatchMessage.connectionsKey] as? Data,
                   let decoded = try? JSONDecoder().decode([TripData].self, from: rawData) {
                    self.connectionResults = decoded
                } else {
                    self.connectionsError = "Keine Verbindungen gefunden"
                }
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.connectionsLoading = false
                self.connectionsError = error.localizedDescription
            }
        }
    }

    private func requestViaiPhone(stationID: String, stationName: String) {
        isLoading = true
        lastError = nil
        log("requestViaiPhone: sende WCSession-Nachricht")

        let msg: [String: Any] = [
            WatchMessage.requestDepartures: true,
            WatchMessage.stationIDKey: stationID,
            WatchMessage.stationNameKey: stationName
        ]

        WCSession.default.sendMessage(msg) { [weak self] reply in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false
                self.log("requestViaiPhone: Antwort erhalten, verarbeite…")
                self.handleDepartureReply(reply)
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false
                self.lastError = error.localizedDescription
                self.log("requestViaiPhone: Fehler – \(error.localizedDescription)")
            }
        }
    }

    private func requestDirectly(stationID: String) async {
        isLoading = true
        lastError = nil
        log("requestDirectly: starte direkte API-Anfrage für \(stationID)")

        if let result = await WatchDirectService.shared.fetchDepartures(stationID: stationID) {
            log("requestDirectly: \(result.count) Abfahrten erhalten")
            departures = result
        } else {
            log("requestDirectly: Fehler – keine Daten zurückgekommen")
            lastError = "Keine Verbindung"
        }
        isLoading = false
    }

    private func handleDepartureReply(_ reply: [String: Any]) {
        guard let rawData = reply[WatchMessage.departuresKey] as? Data else {
            log("handleDepartureReply: kein 'departures'-Key in Antwort (Keys: \(reply.keys.joined(separator: ",")))")
            return
        }
        log("handleDepartureReply: \(rawData.count) Bytes empfangen")
        do {
            let decoded = try JSONDecoder().decode([WatchDeparture].self, from: rawData)
            log("handleDepartureReply: \(decoded.count) Abfahrten dekodiert")
            departures = decoded
        } catch {
            log("handleDepartureReply: Decode-Fehler – \(error)")
            if let jsonStr = String(data: rawData.prefix(300), encoding: .utf8) {
                log("handleDepartureReply: JSON-Ausschnitt: \(jsonStr)")
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let stateStr: String
        switch activationState {
        case .activated:   stateStr = "aktiviert"
        case .inactive:    stateStr = "inaktiv"
        case .notActivated: stateStr = "nicht aktiviert"
        @unknown default:  stateStr = "unbekannt"
        }
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.log("WCSession aktiviert: state=\(stateStr), erreichbar=\(session.isReachable)" + (error.map { ", Fehler=\($0.localizedDescription)" } ?? ""))
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.log("Erreichbarkeit geändert: \(session.isReachable ? "erreichbar" : "nicht erreichbar")")
            if session.isReachable && self.needsInitialData {
                self.requestInitialData()
            }
        }
    }

    // Sofort-Benachrichtigung vom iPhone wenn sich Fahrtdaten geändert haben
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        if message["tripDataDidChange"] != nil {
            Task { @MainActor in
                self.log("didReceiveMessage: tripDataDidChange")
                self.onContextUpdated?()
            }
        }
    }

    // Verzögerte Benachrichtigung (wenn Watch beim Senden nicht erreichbar war)
    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any]) {
        if userInfo["tripDataDidChange"] != nil {
            Task { @MainActor in
                self.log("didReceiveUserInfo: tripDataDidChange")
                self.onContextUpdated?()
            }
        }
    }

    // Kontextaktualisierungen vom iPhone annehmen (z.B. vorberechnete Abfahrten + Credentials)
    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.log("didReceiveApplicationContext: Keys=[\(applicationContext.keys.joined(separator: ","))]")
        }
        if let rawData = applicationContext[WatchMessage.departuresKey] as? Data,
           let decoded = try? JSONDecoder().decode([WatchDeparture].self, from: rawData) {
            Task { @MainActor in
                self.log("appContext: \(decoded.count) Abfahrten via Context")
                self.departures = decoded
            }
        }

        // Trip-Daten vom iPhone in lokale UserDefaults speichern
        let defaults = UserDefaults(suiteName: "group.com.stefanfriedrich.rnvapp")
        var tripDataUpdated = false
        if let tripData = applicationContext["plannedTripData"] as? Data {
            defaults?.set(tripData, forKey: "plannedTripData")
            tripDataUpdated = true
        }
        if let savedData = applicationContext["savedTripData"] as? Data {
            defaults?.set(savedData, forKey: "savedTripData")
            tripDataUpdated = true
        }
        if tripDataUpdated {
            Task { @MainActor in
                self.log("appContext: Fahrtdaten gespeichert")
                self.onContextUpdated?()
            }
        }

        if let creds = applicationContext["watchCredentials"] as? [String: Any],
           let clientID = creds["clientID"] as? String,
           let clientSecret = creds["clientSecret"] as? String,
           let tenantID = creds["tenantID"] as? String,
           let resource = creds["resource"] as? String,
           let graphQLURL = creds["graphQLURL"] as? String {
            let credentials = WatchDirectService.Credentials(
                clientID: clientID,
                clientSecret: clientSecret,
                tenantID: tenantID,
                resource: resource,
                graphQLURL: graphQLURL,
                accessToken: creds["accessToken"] as? String,
                tokenExpiry: creds["tokenExpiry"] as? TimeInterval
            )
            Task { @MainActor in
                WatchDirectService.shared.saveCredentials(credentials)
                self.log("appContext: Credentials gespeichert (clientID=\(clientID.prefix(8))…)")
                self.onContextUpdated?()
            }
        }
    }
}
