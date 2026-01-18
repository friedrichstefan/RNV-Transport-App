//
//  GraphQLService.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 09.01.26.
//

import Foundation
import Combine

// MARK: - Datenmodelle (bleiben gleich)

struct Station: Identifiable, Codable {
    let id = UUID()
    let hafasID: String
    let globalID: String
    let longName: String
    
    enum CodingKeys: String, CodingKey {
        case hafasID, globalID, longName
    }
}

struct Trip: Identifiable, Codable {
    var id = UUID()
    let startTime: String
    let endTime: String
    let interchanges: Int
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
    let type: String // "TimedLeg", "InterchangeLeg", "ContinuousLeg"
    let mode: String? // für Walk/Interchange
    
    // Für TimedLeg (Fahrt mit ÖPNV)
    let boardStopName: String?
    let alightStopName: String?
    let departureTime: String?
    let arrivalTime: String?
    let estimatedDepartureTime: String?
    let estimatedArrivalTime: String?
    
    // Service-Informationen
    let serviceType: String?
    let serviceName: String?
    let serviceDescription: String?
    let destinationLabel: String?
}

// MARK: - GraphQL Service

class GraphQLService: ObservableObject {
    @Published var stations: [Station] = []
    @Published var trips: [Trip] = []
    @Published var detailedTrips: [DetailedTrip] = []
    @Published var isLoading = false
    
    // ✅ GEÄNDERT: protected statt private für Vererbung
    internal var baseURL: String
    
    init() {
        // Lade URL aus Bundle mit Fallback
        self.baseURL = Self.loadGraphQLURL()
        print("📡 [GraphQL] Service initialisiert mit URL: \(self.baseURL)")
    }

    private static func loadGraphQLURL() -> String {
        let fallbackURL = "https://graphql-sandbox-dds.rnv-online.de/"
        
        // 1. Versuche Bundle-URL zu laden
        guard let bundleURL = Bundle.main.object(forInfoDictionaryKey: "RNV_GRAPHQL_URL") as? String else {
            print("⚠️ [GraphQL] RNV_GRAPHQL_URL nicht in Info.plist gefunden")
            return fallbackURL
        }
        
        // 2. Prüfe ob Variable aufgelöst wurde
        guard !bundleURL.contains("$(") else {
            print("❌ [GraphQL] Variable nicht aufgelöst: \(bundleURL)")
            return fallbackURL
        }
        
        // 3. Prüfe ob URL gültig ist
        guard !bundleURL.isEmpty, URL(string: bundleURL) != nil else {
            print("❌ [GraphQL] Ungültige URL: \(bundleURL)")
            return fallbackURL
        }
        
        print("✅ [GraphQL] URL erfolgreich geladen: \(bundleURL)")
        return bundleURL
    }
    
    // MARK: - Haltestellen suchen (GPS-basiert)
    
    func searchStations(lat: Double, lon: Double, accessToken: String) async {
        DispatchQueue.main.async { self.isLoading = true }
        
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
        
        await executeQuery(query: query, accessToken: accessToken) { [weak self] (data: Data) in
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let data = json["data"] as? [String: Any],
               let stations = data["stations"] as? [String: Any],
               let elements = stations["elements"] as? [[String: Any]] {
                
                let parsedStations = elements.compactMap { element -> Station? in
                    guard let hafasID = element["hafasID"] as? String,
                          let globalID = element["globalID"] as? String,
                          let longName = element["longName"] as? String else { return nil }
                    
                    return Station(hafasID: hafasID, globalID: globalID, longName: longName)
                }
                
                DispatchQueue.main.async {
                    self?.stations = parsedStations
                    self?.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Haltestellen suchen (Name-basiert)
    
    func searchStationsByName(name: String, accessToken: String) async {
        DispatchQueue.main.async { self.isLoading = true }
        
        let query = """
        {
          stations(first: 20, name: "\(name)") {
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
        
        await executeQuery(query: query, accessToken: accessToken) { [weak self] (data: Data) in
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let data = json["data"] as? [String: Any],
               let stations = data["stations"] as? [String: Any],
               let elements = stations["elements"] as? [[String: Any]] {
                
                let parsedStations = elements.compactMap { element -> Station? in
                    guard let hafasID = element["hafasID"] as? String,
                          let globalID = element["globalID"] as? String,
                          let longName = element["longName"] as? String else { return nil }
                    
                    return Station(hafasID: hafasID, globalID: globalID, longName: longName)
                }
                
                DispatchQueue.main.async {
                    self?.stations = parsedStations
                    self?.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Verbindungen suchen
    
    func getConnections(fromGlobalID: String, toGlobalID: String, accessToken: String, departureTime: String? = nil) async {
        DispatchQueue.main.async { self.isLoading = true }
        
        let searchTime = departureTime ?? ISO8601DateFormatter().string(from: Date())
        
        let query = """
        {
          trips(
            originGlobalID: "\(fromGlobalID)"
            destinationGlobalID: "\(toGlobalID)"
            departureTime: "\(searchTime)"
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
        
        await executeQuery(query: query, accessToken: accessToken) { [weak self] (data: Data) in
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let data = json["data"] as? [String: Any],
               let trips = data["trips"] as? [[String: Any]] {
                
                let parsedTrips = trips.compactMap { trip -> DetailedTrip? in
                    guard let startTimeDict = trip["startTime"] as? [String: Any],
                          let startTime = startTimeDict["isoString"] as? String,
                          let endTimeDict = trip["endTime"] as? [String: Any],
                          let endTime = endTimeDict["isoString"] as? String,
                          let interchanges = trip["interchanges"] as? Int,
                          let legs = trip["legs"] as? [[String: Any]] else { return nil }
                    
                    let parsedLegs = legs.compactMap { leg -> TripLeg? in
                        // TimedLeg (Fahrt mit ÖPNV)
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
                                type: "TimedLeg",
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
                        }
                        // InterchangeLeg oder ContinuousLeg (Fußweg)
                        else if let mode = leg["mode"] as? String {
                            return TripLeg(
                                type: mode == "WALK" ? "ContinuousLeg" : "InterchangeLeg",
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
                
                DispatchQueue.main.async {
                    self?.detailedTrips = parsedTrips
                    self?.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Live-Updates für Trip abrufen (für LiveActivityManager)
    
    func getLiveTripUpdates(tripId: String, accessToken: String) async -> DetailedTrip? {
        print("🔄 [GraphQL] Rufe Live-Updates ab für Trip: \(tripId)")
        print("⚠️ [GraphQL] Live-Update API noch nicht implementiert")
        return nil
    }
    
    // ✅ GEÄNDERT: internal für Vererbung + async completion
    internal func executeQuery(query: String, accessToken: String, completion: @escaping (Data) -> Void) async {
        guard let url = URL(string: baseURL) else {
            print("❌ [GraphQL] Ungültige URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let body = ["query": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Response-Logging
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 [GraphQL] Response Status: \(httpResponse.statusCode)")
            }
            
            completion(data)
        } catch {
            print("❌ [GraphQL] Netzwerkfehler: \(error.localizedDescription)")
            DispatchQueue.main.async { self.isLoading = false }
        }
    }
}
