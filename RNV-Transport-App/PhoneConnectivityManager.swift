// Empfängt Nachrichten von der Apple Watch und antwortet mit Abfahrtsdaten.
// Muss in der iPhone App initialisiert werden (z.B. in AppDelegate oder App).

import Foundation
import WatchConnectivity

private enum WatchMessageKey {
    static let requestDepartures  = "requestDepartures"
    static let stationID          = "stationID"
    static let stationName        = "stationName"
    static let departures         = "departures"
    static let requestConnections = "requestConnections"
    static let fromID             = "fromID"
    static let toID               = "toID"
    static let connections        = "connections"
    static let requestStationSearch    = "requestStationSearch"
    static let searchQuery             = "searchQuery"
    static let stationSearchResults    = "stationSearchResults"
}

final class PhoneConnectivityManager: NSObject {
    static let shared = PhoneConnectivityManager()

    // Wird von außen gesetzt, damit wir API-Abfragen machen können
    var graphQLService: GraphQLService?
    var authService: AuthService?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Credentials an Watch übertragen

    func pushCredentialsToWatch(token: String, tokenExpiry: Date) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled
        else { return }

        let config = SecureConfigurationManager.shared
        guard let clientID = config.clientID, !clientID.isEmpty, !clientID.hasPrefix("$("),
              let clientSecret = config.clientSecret, !clientSecret.isEmpty, !clientSecret.hasPrefix("$("),
              let tenantID = config.tenantID, !tenantID.isEmpty, !tenantID.hasPrefix("$("),
              let resource = config.resource, !resource.isEmpty, !resource.hasPrefix("$("),
              let graphQLURL = config.graphQLURL, !graphQLURL.isEmpty, !graphQLURL.hasPrefix("$(")
        else { return }

        let context: [String: Any] = [
            "watchCredentials": [
                "clientID": clientID,
                "clientSecret": clientSecret,
                "tenantID": tenantID,
                "resource": resource,
                "graphQLURL": graphQLURL,
                "accessToken": token,
                "tokenExpiry": tokenExpiry.timeIntervalSince1970
            ]
        ]

        try? WCSession.default.updateApplicationContext(context)
    }

    /// Benachrichtigt die Watch-App, dass sich Fahrtdaten geändert haben.
    /// Nutzt sendMessage wenn Watch erreichbar, sonst transferUserInfo als Fallback.
    func notifyTripUpdate() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled
        else { return }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["tripDataDidChange": true], replyHandler: nil, errorHandler: nil)
        } else {
            WCSession.default.transferUserInfo(["tripDataDidChange": true])
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {

        if message[WatchMessageKey.requestDepartures] != nil,
           let stationID = message[WatchMessageKey.stationID] as? String {
            Task { await fetchAndReply(stationID: stationID, replyHandler: replyHandler) }
        } else if message[WatchMessageKey.requestConnections] != nil,
                  let fromID = message[WatchMessageKey.fromID] as? String,
                  let toID   = message[WatchMessageKey.toID]   as? String {
            Task { await fetchConnectionsAndReply(fromID: fromID, toID: toID, replyHandler: replyHandler) }
        } else if message[WatchMessageKey.requestStationSearch] != nil,
                  let query = message[WatchMessageKey.searchQuery] as? String {
            Task { await searchStationsAndReply(query: query, replyHandler: replyHandler) }
        } else {
            replyHandler([:])
        }
    }

    @MainActor
    private func searchStationsAndReply(query: String,
                                        replyHandler: @escaping ([String: Any]) -> Void) async {
        guard let graphQL = graphQLService,
              let auth = authService else {
            replyHandler([:]); return
        }

        let token: String
        if let existing = auth.accessToken {
            token = existing
        } else {
            await auth.authenticate()
            guard let fresh = auth.accessToken else { replyHandler([:]); return }
            token = fresh
        }

        await graphQL.searchStationsByName(name: query, accessToken: token)
        let results: [WatchStationResult] = graphQL.stations.prefix(15).map {
            WatchStationResult(id: $0.globalID, name: $0.longName)
        }

        if let data = try? JSONEncoder().encode(results) {
            replyHandler([WatchMessageKey.stationSearchResults: data])
        } else {
            replyHandler([:])
        }
    }

    // MARK: - Abfahrten holen und zurückschicken

    @MainActor
    private func fetchAndReply(stationID: String,
                               replyHandler: @escaping ([String: Any]) -> Void) async {
        guard let graphQL = graphQLService,
              let auth = authService else {
            replyHandler([:])
            return
        }

        let token: String
        if let existing = auth.accessToken {
            token = existing
        } else {
            await auth.authenticate()
            guard let fresh = auth.accessToken else { replyHandler([:]); return }
            token = fresh
        }

        let result = await graphQL.getDepartures(globalID: stationID, accessToken: token)
        let watchDepartures: [WatchDepartureResponse] = result.departures.map { dep in
            WatchDepartureResponse(
                id: dep.id.uuidString,
                lineName: dep.lineName,
                direction: dep.direction,
                scheduledTime: dep.scheduledDeparture,
                estimatedTime: dep.estimatedDeparture,
                serviceType: dep.serviceType,
                delayMinutes: dep.delayMinutes
            )
        }

        if let data = try? JSONEncoder().encode(watchDepartures) {
            replyHandler([WatchMessageKey.departures: data])
        } else {
            replyHandler([:])
        }
    }

    @MainActor
    private func fetchConnectionsAndReply(fromID: String, toID: String,
                                          replyHandler: @escaping ([String: Any]) -> Void) async {
        guard let graphQL = graphQLService,
              let auth = authService else {
            replyHandler([:])
            return
        }

        let token: String
        if let existing = auth.accessToken {
            token = existing
        } else {
            await auth.authenticate()
            guard let fresh = auth.accessToken else { replyHandler([:]); return }
            token = fresh
        }

        let trips = await graphQL.fetchConnectionsForWatch(fromGlobalID: fromID, toGlobalID: toID, accessToken: token)
        if let data = try? JSONEncoder().encode(trips) {
            replyHandler([WatchMessageKey.connections: data])
        } else {
            replyHandler([:])
        }
    }
}

// MARK: - Codable Response-Modelle (spiegeln Watch-Typen)

private struct WatchDepartureResponse: Codable {
    let id: String
    let lineName: String
    let direction: String
    let scheduledTime: String
    let estimatedTime: String?
    let serviceType: String?
    let delayMinutes: Int?
}

private struct WatchStationResult: Codable {
    let id: String
    let name: String
}

