//
//  GraphQLService.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 09.01.26.
//

import Foundation
import Combine

// MARK: - Data Models

struct Station: Identifiable, Codable {
    let hafasID: String
    let globalID: String
    let longName: String

    /// Stabile ID basierend auf globalID – verhindert doppelte SwiftUI-Redraws nach Decode
    var id: String { globalID }
}

struct Trip: Identifiable, Codable {
    var id = UUID()
    let startTime: String
    let endTime: String
    let interchanges: Int
}

// MARK: - Leg Type Enum (replaces raw strings)

enum LegType: String, Codable {
    case timedLeg = "TimedLeg"
    case continuousLeg = "ContinuousLeg"
    case interchangeLeg = "InterchangeLeg"
}

struct DetailedTrip: Identifiable {
    let id = UUID()
    let startTime: String
    let endTime: String
    let interchanges: Int
    let legs: [TripLeg]
}

struct TripLeg: Identifiable {
    let id = UUID()
    let type: LegType
    let mode: String?

    let boardStopName: String?
    let alightStopName: String?
    let departureTime: String?
    let arrivalTime: String?
    let estimatedDepartureTime: String?
    let estimatedArrivalTime: String?

    let serviceType: String?
    let serviceName: String?
    let serviceDescription: String?
    let destinationLabel: String?

    /// Convenience: is this a timed (vehicle) leg?
    var isTimedLeg: Bool { type == .timedLeg }
}

// MARK: - GraphQL Error

struct GraphQLError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - GraphQL Service

@MainActor
class GraphQLService: ObservableObject {
    @Published var stations: [Station] = []
    @Published var trips: [Trip] = []
    @Published var detailedTrips: [DetailedTrip] = []
    @Published var isLoading = false
    @Published var lastError: GraphQLError?

    internal var baseURL: String

    init() {
        self.baseURL = Self.loadGraphQLURL()
        print("📡 [GraphQL] Service initialisiert mit URL: \(self.baseURL)")
    }

    private static func loadGraphQLURL() -> String {
        let fallbackURL = "https://graphql-sandbox-dds.rnv-online.de/"

        guard let bundleURL = Bundle.main.object(forInfoDictionaryKey: "RNV_GRAPHQL_URL") as? String else {
            print("⚠️ [GraphQL] RNV_GRAPHQL_URL nicht in Info.plist gefunden")
            return fallbackURL
        }

        // Anführungszeichen entfernen, falls xcconfig-Wert mit Quotes gespeichert ist (z.B. "https://...")
        let trimmedURL = bundleURL.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        guard !trimmedURL.contains("$(") else {
            print("❌ [GraphQL] Variable nicht aufgelöst: \(trimmedURL)")
            return fallbackURL
        }

        guard !trimmedURL.isEmpty, URL(string: trimmedURL) != nil else {
            print("❌ [GraphQL] Ungültige URL: \(trimmedURL)")
            return fallbackURL
        }

        print("✅ [GraphQL] URL erfolgreich geladen: \(trimmedURL)")
        return trimmedURL
    }

    // MARK: - Input Sanitization

    /// Sanitizes user input to prevent GraphQL injection.
    private func sanitize(_ input: String) -> String {
        return input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    // MARK: - GraphQL Error Extraction

    private func extractGraphQLErrors(from data: Data) -> GraphQLError? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [[String: Any]],
              let firstMessage = errors.first?["message"] as? String else {
            return nil
        }
        return GraphQLError(message: firstMessage)
    }

    // MARK: - Station Search (Location-Based)

    func searchStations(lat: Double, lon: Double, accessToken: String) async {
        isLoading = true
        lastError = nil

        let query = """
        {
          stations(first: 10, lat: \(lat), long: \(lon), distance: 2.0) {
            elements {
              ... on Station {
                hafasID
                globalID
                longName
              }
            }
          }
        }
        """

        do {
            let data = try await executeQuery(query: query, accessToken: accessToken)

            if let gqlError = extractGraphQLErrors(from: data) {
                lastError = gqlError
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseData = json["data"] as? [String: Any],
               let stations = responseData["stations"] as? [String: Any],
               let elements = stations["elements"] as? [[String: Any]] {

                self.stations = elements.compactMap { element -> Station? in
                    guard let hafasID = element["hafasID"] as? String,
                          let globalID = element["globalID"] as? String,
                          let longName = element["longName"] as? String else { return nil }
                    return Station(hafasID: hafasID, globalID: globalID, longName: longName)
                }
            }
        } catch {
            lastError = GraphQLError(message: error.localizedDescription)
        }

        isLoading = false
    }

    // MARK: - Station Search (Name-Based)

    func searchStationsByName(name: String, accessToken: String) async {
        isLoading = true
        lastError = nil

        let safeName = sanitize(name)

        let query = """
        {
          stations(first: 20, name: "\(safeName)") {
            elements {
              ... on Station {
                hafasID
                globalID
                longName
              }
            }
          }
        }
        """

        do {
            let data = try await executeQuery(query: query, accessToken: accessToken)

            if let gqlError = extractGraphQLErrors(from: data) {
                lastError = gqlError
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseData = json["data"] as? [String: Any],
               let stations = responseData["stations"] as? [String: Any],
               let elements = stations["elements"] as? [[String: Any]] {

                self.stations = elements.compactMap { element -> Station? in
                    guard let hafasID = element["hafasID"] as? String,
                          let globalID = element["globalID"] as? String,
                          let longName = element["longName"] as? String else { return nil }
                    return Station(hafasID: hafasID, globalID: globalID, longName: longName)
                }
            }
        } catch {
            lastError = GraphQLError(message: error.localizedDescription)
        }

        isLoading = false
    }

    // MARK: - Get Connections

    func getConnections(fromGlobalID: String, toGlobalID: String, accessToken: String, departureTime: String? = nil) async {
        isLoading = true
        lastError = nil

        let searchTime = departureTime ?? ISO8601DateFormatter().string(from: Date())

        let safeFrom = sanitize(fromGlobalID)
        let safeTo = sanitize(toGlobalID)
        let safeTime = sanitize(searchTime)

        let query = """
        {
          trips(
            originGlobalID: "\(safeFrom)"
            destinationGlobalID: "\(safeTo)"
            departureTime: "\(safeTime)"
          ) {
            startTime {
              isoString
            }
            endTime {
              isoString
            }
            interchanges
            legs {
              ... on InterchangeLeg {
                mode
              }
              ... on ContinuousLeg {
                mode
              }
              ... on TimedLeg {
                board {
                  point {
                    ... on StopPoint {
                      ref
                      stopPointName
                    }
                  }
                  estimatedTime {
                    isoString
                  }
                  timetabledTime {
                    isoString
                  }
                }
                alight {
                  point {
                    ... on StopPoint {
                      ref
                      stopPointName
                    }
                  }
                  estimatedTime {
                    isoString
                  }
                  timetabledTime {
                    isoString
                  }
                }
                service {
                  type
                  name
                  description
                  destinationLabel
                }
              }
            }
          }
        }
        """

        do {
            let data = try await executeQuery(query: query, accessToken: accessToken)

            if let gqlError = extractGraphQLErrors(from: data) {
                lastError = gqlError
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseData = json["data"] as? [String: Any],
               let trips = responseData["trips"] as? [[String: Any]] {

                self.detailedTrips = trips.compactMap { trip -> DetailedTrip? in
                    guard let startTimeDict = trip["startTime"] as? [String: Any],
                          let startTime = startTimeDict["isoString"] as? String,
                          let endTimeDict = trip["endTime"] as? [String: Any],
                          let endTime = endTimeDict["isoString"] as? String,
                          let interchanges = trip["interchanges"] as? Int,
                          let legs = trip["legs"] as? [[String: Any]] else { return nil }

                    let parsedLegs = legs.compactMap { leg -> TripLeg? in
                        if let board = leg["board"] as? [String: Any],
                           let alight = leg["alight"] as? [String: Any],
                           let service = leg["service"] as? [String: Any] {

                            let boardPoint = board["point"] as? [String: Any]
                            let alightPoint = alight["point"] as? [String: Any]
                            let boardTimetabled = board["timetabledTime"] as? [String: Any]
                            let boardEstimated = board["estimatedTime"] as? [String: Any]
                            let alightTimetabled = alight["timetabledTime"] as? [String: Any]
                            let alightEstimated = alight["estimatedTime"] as? [String: Any]

                            return TripLeg(
                                type: .timedLeg,
                                mode: nil,
                                boardStopName: boardPoint?["stopPointName"] as? String,
                                alightStopName: alightPoint?["stopPointName"] as? String,
                                departureTime: boardTimetabled?["isoString"] as? String,
                                arrivalTime: alightTimetabled?["isoString"] as? String,
                                estimatedDepartureTime: boardEstimated?["isoString"] as? String,
                                estimatedArrivalTime: alightEstimated?["isoString"] as? String,
                                serviceType: service["type"] as? String,
                                serviceName: service["name"] as? String,
                                serviceDescription: service["description"] as? String,
                                destinationLabel: service["destinationLabel"] as? String
                            )
                        } else if let mode = leg["mode"] as? String {
                            return TripLeg(
                                type: mode == "WALK" ? .continuousLeg : .interchangeLeg,
                                mode: mode,
                                boardStopName: nil,
                                alightStopName: nil,
                                departureTime: nil,
                                arrivalTime: nil,
                                estimatedDepartureTime: nil,
                                estimatedArrivalTime: nil,
                                serviceType: nil,
                                serviceName: mode == "WALK" ? "Fußweg" : "Umstieg",
                                serviceDescription: nil,
                                destinationLabel: nil
                            )
                        }
                        return nil
                    }

                    return DetailedTrip(
                        startTime: startTime,
                        endTime: endTime,
                        interchanges: interchanges,
                        legs: parsedLegs
                    )
                }
            }
        } catch {
            lastError = GraphQLError(message: error.localizedDescription)
        }

        isLoading = false
    }

    // MARK: - Live Updates

    func getLiveTripUpdates(tripId: String, accessToken: String) async -> DetailedTrip? {
        print("🔄 [GraphQL] Rufe Live-Updates ab für Trip: \(tripId)")
        print("⚠️ [GraphQL] Live-Update API noch nicht implementiert")
        return nil
    }

    // MARK: - Execute Query

    internal func executeQuery(query: String, accessToken: String) async throws -> Data {
        guard let url = URL(string: baseURL) else {
            throw GraphQLError(message: "Ungültige URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body = ["query": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("📡 [GraphQL] Response Status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                throw GraphQLError(message: "HTTP-Fehler: \(httpResponse.statusCode)")
            }
        }

        return data
    }
}
