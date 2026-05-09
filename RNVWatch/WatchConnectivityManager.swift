// Kommunikation zwischen Watch und iPhone über WatchConnectivity.
// Die Watch kann Abfahrten für eine Haltestelle beim iPhone anfordern.

import Foundation
import WatchConnectivity
import Combine

// Nachrichtentypen (müssen mit iPhone-Seite übereinstimmen)
enum WatchMessage {
    static let requestDepartures = "requestDepartures"
    static let stationIDKey      = "stationID"
    static let stationNameKey    = "stationName"
    static let departuresKey     = "departures"
}

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var departures: [WatchDeparture] = []
    @Published var isLoading = false
    @Published var lastError: String? = nil
    @Published var isReachable = false

    var onContextUpdated: (() -> Void)? = nil

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Abfahrten anfragen

    func requestDepartures(stationID: String, stationName: String) {
        #if targetEnvironment(simulator) && DEBUG
        isLoading = true
        lastError = nil
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                self.departures = WatchDemoData.departures
                self.isLoading  = false
            }
        }
        #else
        if WCSession.default.isReachable {
            requestViaiPhone(stationID: stationID, stationName: stationName)
        } else if WatchDirectService.shared.hasCredentials {
            Task { await requestDirectly(stationID: stationID) }
        } else {
            lastError = "iPhone nicht erreichbar"
        }
        #endif
    }

    private func requestViaiPhone(stationID: String, stationName: String) {
        isLoading = true
        lastError = nil

        let msg: [String: Any] = [
            WatchMessage.requestDepartures: true,
            WatchMessage.stationIDKey: stationID,
            WatchMessage.stationNameKey: stationName
        ]

        WCSession.default.sendMessage(msg) { [weak self] reply in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false
                self.handleDepartureReply(reply)
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false
                self.lastError = error.localizedDescription
            }
        }
    }

    private func requestDirectly(stationID: String) async {
        isLoading = true
        lastError = nil

        if let result = await WatchDirectService.shared.fetchDepartures(stationID: stationID) {
            departures = result
        } else {
            lastError = "Keine Verbindung"
        }
        isLoading = false
    }

    private func handleDepartureReply(_ reply: [String: Any]) {
        guard let rawData = reply[WatchMessage.departuresKey] as? Data else { return }
        let decoded = (try? JSONDecoder().decode([WatchDeparture].self, from: rawData)) ?? []
        departures = decoded
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    // Sofort-Benachrichtigung vom iPhone wenn sich Fahrtdaten geändert haben
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        if message["tripDataDidChange"] != nil {
            Task { @MainActor in self.onContextUpdated?() }
        }
    }

    // Kontextaktualisierungen vom iPhone annehmen (z.B. vorberechnete Abfahrten + Credentials)
    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        if let rawData = applicationContext[WatchMessage.departuresKey] as? Data,
           let decoded = try? JSONDecoder().decode([WatchDeparture].self, from: rawData) {
            Task { @MainActor in self.departures = decoded }
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
                self.onContextUpdated?()
            }
        }
    }
}
