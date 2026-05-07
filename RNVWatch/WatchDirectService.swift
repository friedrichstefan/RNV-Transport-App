// Ermöglicht der Watch selbständige API-Anfragen wenn das iPhone nicht erreichbar ist.
// Credentials werden vom iPhone via ApplicationContext übertragen und lokal gecacht.

import Foundation

@MainActor
class WatchDirectService {
    static let shared = WatchDirectService()

    private let credentialsKey = "watchCachedCredentials"

    struct Credentials: Codable {
        let clientID: String
        let clientSecret: String
        let tenantID: String
        let resource: String
        let graphQLURL: String
        var accessToken: String?
        var tokenExpiry: TimeInterval?
    }

    private init() {}

    // MARK: - Credentials

    func saveCredentials(_ creds: Credentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        UserDefaults.standard.set(data, forKey: credentialsKey)
    }

    func loadCredentials() -> Credentials? {
        guard let data = UserDefaults.standard.data(forKey: credentialsKey) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    var hasCredentials: Bool { loadCredentials() != nil }

    // MARK: - Token

    func getValidToken() async -> String? {
        guard var creds = loadCredentials() else { return nil }

        if let token = creds.accessToken,
           let expiry = creds.tokenExpiry,
           Date().timeIntervalSince1970 < expiry - 60 {
            return token
        }

        guard let token = await authenticate(creds: creds) else { return nil }

        creds.accessToken = token
        creds.tokenExpiry = Date().timeIntervalSince1970 + 3600
        saveCredentials(creds)
        return token
    }

    private func authenticate(creds: Credentials) async -> String? {
        let urlString = "https://login.microsoftonline.com/\(creds.tenantID)/oauth2/token"
        guard let url = URL(string: urlString),
              let encodedID = creds.clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedSecret = creds.clientSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedRes = creds.resource.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials&client_id=\(encodedID)&client_secret=\(encodedSecret)&resource=\(encodedRes)"
            .data(using: .utf8)
        request.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String
        else { return nil }

        return token
    }

    // MARK: - Departures

    func fetchDepartures(stationID: String) async -> [WatchDeparture]? {
        guard let creds = loadCredentials(),
              let token = await getValidToken()
        else { return nil }

        let hubNames = ["Mannheim Hauptbahnhof", "Heidelberg Hauptbahnhof", "Paradeplatz"]
        var hubIDs: [String] = []
        for name in hubNames {
            if let id = await resolveStationID(name: name, token: token, graphQLURL: creds.graphQLURL) {
                hubIDs.append(id)
            }
        }

        guard !hubIDs.isEmpty else { return nil }

        let time = ISO8601DateFormatter().string(from: Date())
        var allDepartures: [WatchDeparture] = []

        for hubID in hubIDs.prefix(3) {
            guard hubID != stationID else { continue }
            let deps = await fetchLegs(from: stationID, to: hubID, time: time, token: token, graphQLURL: creds.graphQLURL)
            allDepartures.append(contentsOf: deps)
        }

        var seen = Set<String>()
        var result = allDepartures.filter { seen.insert("\($0.lineName)-\($0.scheduledTime)").inserted }
        result.sort {
            let a = WatchDateHelper.parse($0.scheduledTime) ?? .distantFuture
            let b = WatchDateHelper.parse($1.scheduledTime) ?? .distantFuture
            return a < b
        }
        return result
    }

    private func resolveStationID(name: String, token: String, graphQLURL: String) async -> String? {
        let safe = name.replacingOccurrences(of: "\"", with: "")
        let query = """
        { stations(first: 1, name: "\(safe)") { elements { ... on Station { globalID } } } }
        """
        guard let data = try? await execute(query: query, token: token, graphQLURL: graphQLURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = json["data"] as? [String: Any],
              let s = d["stations"] as? [String: Any],
              let elements = s["elements"] as? [[String: Any]],
              let globalID = elements.first?["globalID"] as? String
        else { return nil }
        return globalID
    }

    private func fetchLegs(from originID: String, to destID: String, time: String, token: String, graphQLURL: String) async -> [WatchDeparture] {
        let query = """
        {
          trips(
            originGlobalID: "\(originID)"
            destinationGlobalID: "\(destID)"
            departureTime: "\(time)"
          ) {
            legs {
              ... on TimedLeg {
                board {
                  timetabledTime { isoString }
                  estimatedTime { isoString }
                }
                service {
                  name
                  type
                  destinationLabel
                }
              }
            }
          }
        }
        """

        guard let data = try? await execute(query: query, token: token, graphQLURL: graphQLURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = json["data"] as? [String: Any],
              let trips = d["trips"] as? [[String: Any]]
        else { return [] }

        return trips.compactMap { trip -> WatchDeparture? in
            guard let legs = trip["legs"] as? [[String: Any]],
                  let firstLeg = legs.first(where: { $0["board"] != nil }),
                  let board = firstLeg["board"] as? [String: Any],
                  let service = firstLeg["service"] as? [String: Any],
                  let lineName = service["name"] as? String,
                  let direction = service["destinationLabel"] as? String,
                  let timetabled = (board["timetabledTime"] as? [String: Any])?["isoString"] as? String,
                  timetabled != "null", !timetabled.isEmpty
            else { return nil }

            let estimated = (board["estimatedTime"] as? [String: Any])?["isoString"] as? String
            let serviceType = service["type"] as? String

            let delayMinutes: Int? = {
                guard let s = WatchDateHelper.parse(timetabled),
                      let e = estimated.flatMap({ WatchDateHelper.parse($0) }) else { return nil }
                return max(0, Int(e.timeIntervalSince(s) / 60))
            }()

            return WatchDeparture(
                id: "\(lineName)-\(timetabled)",
                lineName: lineName,
                direction: direction,
                scheduledTime: timetabled,
                estimatedTime: estimated,
                serviceType: serviceType,
                delayMinutes: delayMinutes
            )
        }
    }

    private func execute(query: String, token: String, graphQLURL: String) async throws -> Data {
        guard let url = URL(string: graphQLURL) else { throw URLError(.badURL) }
        let body = try JSONSerialization.data(withJSONObject: ["query": query])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}
