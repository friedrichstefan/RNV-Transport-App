//
//  GraphQLService.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 09.01.26.
//

import Foundation
import Combine

// MARK: - Data Models

struct Station: Identifiable, Codable, Equatable {
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

// MARK: - Occupancy Level Enum

enum OccupancyLevel: String, Codable, CaseIterable {
    case unknown = "UNKNOWN"
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case veryHigh = "VERY_HIGH"
    case full = "FULL"

    /// Initialisiert aus beliebigem API-String (case-insensitive)
    init(from apiValue: String) {
        let normalized = apiValue.uppercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        self = OccupancyLevel(rawValue: normalized) ?? .unknown
    }

    /// Benutzerfreundliche Beschreibung
    var displayText: String {
        switch self {
        case .unknown: return "Keine Daten"
        case .low: return "Gering"
        case .medium: return "Mittel"
        case .high: return "Hoch"
        case .veryHigh: return "Sehr hoch"
        case .full: return "Voll"
        }
    }

    /// Kurztext für kompakte Darstellung
    var shortText: String {
        switch self {
        case .unknown: return "?"
        case .low: return "Gering"
        case .medium: return "Mittel"
        case .high: return "Hoch"
        case .veryHigh: return "Sehr hoch"
        case .full: return "Voll"
        }
    }

    /// SF Symbol Name
    var iconName: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .low: return "person"
        case .medium: return "person.2"
        case .high: return "person.3"
        case .veryHigh: return "person.3.fill"
        case .full: return "exclamationmark.triangle.fill"
        }
    }

    /// Farbe für die UI-Darstellung
    var color: Color {
        switch self {
        case .unknown: return .gray
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        case .full: return .red
        }
    }

    /// Prozentuale Füllung (für Fortschrittsanzeige)
    var fillPercentage: Double {
        switch self {
        case .unknown: return 0
        case .low: return 0.25
        case .medium: return 0.5
        case .high: return 0.75
        case .veryHigh: return 0.9
        case .full: return 1.0
        }
    }

    /// Anzahl gefüllter Personen-Icons (von 3) für kompakte Darstellung
    var filledCount: Int {
        switch self {
        case .unknown: return 1
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .veryHigh: return 3
        case .full: return 3
        }
    }
}

import SwiftUI

struct DetailedTrip: Identifiable {
    let id: UUID
    let startTime: String
    let endTime: String
    let interchanges: Int
    let legs: [TripLeg]

    init(startTime: String, endTime: String, interchanges: Int, legs: [TripLeg]) {
        self.startTime = startTime
        self.endTime = endTime
        self.interchanges = interchanges
        self.legs = legs
        self.id = Self.generateStableID(startTime: startTime, endTime: endTime, legs: legs)
    }

    /// Erzeugt eine deterministische UUID basierend auf Trip-Inhalt.
    /// So bekommt derselbe Trip bei jedem API-Abruf die gleiche ID –
    /// entscheidend für korrekte Live-Activity-Zuordnung.
    private static func generateStableID(startTime: String, endTime: String, legs: [TripLeg]) -> UUID {
        let firstTimedLeg = legs.first(where: { $0.type == .timedLeg })
        let lastTimedLeg = legs.last(where: { $0.type == .timedLeg })
        let stableString = [
            startTime,
            endTime,
            firstTimedLeg?.departureTime ?? "",
            firstTimedLeg?.serviceName ?? "",
            firstTimedLeg?.boardStopName ?? "",
            lastTimedLeg?.alightStopName ?? ""
        ].joined(separator: "|")

        // Deterministischer Hash → UUID (djb2-Variante, 2×64 Bit)
        var h1: UInt64 = 5381
        var h2: UInt64 = 5381
        for (i, byte) in stableString.utf8.enumerated() {
            if i % 2 == 0 {
                h1 = ((h1 &<< 5) &+ h1) &+ UInt64(byte)
            } else {
                h2 = ((h2 &<< 5) &+ h2) &+ UInt64(byte)
            }
        }

        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: h1.bigEndian) { buf in
            for i in 0..<8 { bytes[i] = buf[i] }
        }
        withUnsafeBytes(of: h2.bigEndian) { buf in
            for i in 0..<8 { bytes[i + 8] = buf[i] }
        }
        // UUID Version-5- und Variant-Bits setzen
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

struct IntermediateStop {
    let name: String
    let scheduledTime: String
    let estimatedTime: String?
    let occupancy: OccupancyLevel?
    let latitude: Double?
    let longitude: Double?
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
    var intermediateStops: [IntermediateStop] = []

    /// Auslastung/Kapazität für diesen Leg
    var occupancy: OccupancyLevel?

    /// StopPoint-Referenz des Einstiegs (z.B. "de:08222:2417:1:1") – für nachträgliches Occupancy-Enrichment
    var boardRef: String? = nil

    /// API coordinates for the board stop (avoids geocoding)
    let boardLatitude: Double?
    let boardLongitude: Double?
    /// API coordinates for the alight stop (avoids geocoding)
    let alightLatitude: Double?
    let alightLongitude: Double?

    /// Convenience: is this a timed (vehicle) leg?
    var isTimedLeg: Bool { type == .timedLeg }

    // Initializer mit occupancy (Standard: nil)
    init(
        type: LegType,
        mode: String?,
        boardStopName: String?,
        alightStopName: String?,
        departureTime: String?,
        arrivalTime: String?,
        estimatedDepartureTime: String?,
        estimatedArrivalTime: String?,
        serviceType: String?,
        serviceName: String?,
        serviceDescription: String?,
        destinationLabel: String?,
        intermediateStops: [IntermediateStop] = [],
        occupancy: OccupancyLevel? = nil,
        boardRef: String? = nil,
        boardLatitude: Double? = nil,
        boardLongitude: Double? = nil,
        alightLatitude: Double? = nil,
        alightLongitude: Double? = nil
    ) {
        self.type = type
        self.mode = mode
        self.boardStopName = boardStopName
        self.alightStopName = alightStopName
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
        self.estimatedDepartureTime = estimatedDepartureTime
        self.estimatedArrivalTime = estimatedArrivalTime
        self.serviceType = serviceType
        self.serviceName = serviceName
        self.serviceDescription = serviceDescription
        self.destinationLabel = destinationLabel
        self.intermediateStops = intermediateStops
        self.occupancy = occupancy
        self.boardRef = boardRef
        self.boardLatitude = boardLatitude
        self.boardLongitude = boardLongitude
        self.alightLatitude = alightLatitude
        self.alightLongitude = alightLongitude
    }
}

// MARK: - GraphQL Error

struct GraphQLError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Connection Loading Mode

enum ConnectionLoadingMode {
    case replace
    case prepend
    case append
}

// MARK: - GraphQL Service

@MainActor
class GraphQLService: ObservableObject {
    static let shared = GraphQLService()

    @Published var stations: [Station] = []
    @Published var trips: [Trip] = []
    @Published var detailedTrips: [DetailedTrip] = []
    @Published var isLoading = false
    @Published var lastError: GraphQLError?
    
    internal var baseURL: String
    
    init() {
        self.baseURL = Self.loadGraphQLURL()
#if DEBUG
        print("📡 [GraphQL] Service initialisiert mit URL: \(self.baseURL)")
#endif
    }
    
    private static func loadGraphQLURL() -> String {
        let fallbackURL = "https://graphql-sandbox-dds.rnv-online.de/"
        
        guard let bundleURL = Bundle.main.object(forInfoDictionaryKey: "RNV_GRAPHQL_URL") as? String else {
#if DEBUG
            print("⚠️ [GraphQL] RNV_GRAPHQL_URL nicht in Info.plist gefunden")
#endif
            return fallbackURL
        }
        
        // Anführungszeichen entfernen, falls xcconfig-Wert mit Quotes gespeichert ist (z.B. "https://...")
        let trimmedURL = bundleURL.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        
        guard !trimmedURL.contains("$(") else {
#if DEBUG
            print("❌ [GraphQL] Variable nicht aufgelöst: \(trimmedURL)")
#endif
            return fallbackURL
        }
        
        guard !trimmedURL.isEmpty, URL(string: trimmedURL) != nil else {
#if DEBUG
            print("❌ [GraphQL] Ungültige URL: \(trimmedURL)")
#endif
            return fallbackURL
        }
        
#if DEBUG
        print("✅ [GraphQL] URL erfolgreich geladen: \(trimmedURL)")
#endif
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
    
    // MARK: - Query Execution
    
    /// Base implementation of query execution. Subclasses (e.g. SecureGraphQLService)
    /// can override this to add SSL pinning, request signing, etc.
    internal func executeQuery(query: String, accessToken: String) async throws -> Data {
        guard let url = URL(string: baseURL) else {
            throw GraphQLError(message: "Ungültige URL: \(baseURL)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = ["query": query]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw GraphQLError(message: "JSON Serialization fehlgeschlagen")
        }
        request.httpBody = bodyData
        
#if DEBUG
        print("📡 [GraphQL] Anfrage an: \(url.host ?? "")")
#endif
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
#if DEBUG
            print("📡 [GraphQL] Response Status: \(httpResponse.statusCode)")
#endif
            guard (200...299).contains(httpResponse.statusCode) else {
#if DEBUG
                if let body = String(data: data, encoding: .utf8) {
                    print("❌ [GraphQL] Error body (\(httpResponse.statusCode)): \(body)")
                }
#endif
                throw GraphQLError(message: "HTTP-Fehler: \(httpResponse.statusCode)")
            }
        }
        
#if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📡 [GraphQL] Response: \(jsonString.prefix(200))...")
        }
#endif
        
        return data
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

    func getConnections(fromGlobalID: String, toGlobalID: String, accessToken: String, departureTime: String? = nil, arrivalTime: String? = nil, mode: ConnectionLoadingMode = .replace) async {
        isLoading = true
        lastError = nil

        do {
            let newTrips = try await fetchTrips(fromGlobalID: fromGlobalID, toGlobalID: toGlobalID, accessToken: accessToken, departureTime: departureTime, arrivalTime: arrivalTime)
            switch mode {
            case .replace: self.detailedTrips = newTrips
            case .prepend:
                self.detailedTrips = newTrips + self.detailedTrips
                if self.detailedTrips.count > 50 { self.detailedTrips = Array(self.detailedTrips.prefix(50)) }
            case .append:
                self.detailedTrips.append(contentsOf: newTrips)
                if self.detailedTrips.count > 50 { self.detailedTrips = Array(self.detailedTrips.suffix(50)) }
            }
        } catch {
            lastError = GraphQLError(message: error.localizedDescription)
        }

        isLoading = false
    }

    /// Führt die Verbindungssuche aus und gibt die Ergebnisse direkt zurück, ohne den
    /// @Published-State zu verändern. Wird von PhoneConnectivityManager für Watch-Anfragen genutzt.
    func fetchConnectionsForWatch(fromGlobalID: String, toGlobalID: String, accessToken: String) async -> [TripData] {
        let trips = (try? await fetchTrips(fromGlobalID: fromGlobalID, toGlobalID: toGlobalID, accessToken: accessToken)) ?? []
        return trips.map { trip in
            TripData(
                id: trip.id.uuidString,
                startTime: trip.startTime,
                endTime: trip.endTime,
                interchanges: trip.interchanges,
                startStation: trip.legs.first(where: { $0.isTimedLeg })?.boardStopName ?? "",
                endStation: trip.legs.last(where: { $0.isTimedLeg })?.alightStopName ?? "",
                legs: trip.legs.map { leg in
                    TripLegData(
                        legType: leg.type.rawValue,
                        boardStopName: leg.boardStopName,
                        alightStopName: leg.alightStopName,
                        departureTime: leg.departureTime,
                        arrivalTime: leg.arrivalTime,
                        serviceName: leg.serviceName,
                        serviceType: leg.serviceType,
                        destinationLabel: leg.destinationLabel,
                        intermediateStopNames: leg.intermediateStops.isEmpty ? nil : leg.intermediateStops.map { $0.name }
                    )
                }
            )
        }
    }

    private func fetchTrips(fromGlobalID: String, toGlobalID: String, accessToken: String, departureTime: String? = nil, arrivalTime: String? = nil) async throws -> [DetailedTrip] {
        let safeFrom = sanitize(fromGlobalID)
        let safeTo = sanitize(toGlobalID)

        let timeArgument: String
        if let arrival = arrivalTime {
            timeArgument = "arrivalTime: \"\(sanitize(arrival))\""
        } else {
            let t = departureTime ?? ISO8601DateFormatter().string(from: Date())
            timeArgument = "departureTime: \"\(sanitize(t))\""
        }

        #if DEBUG
        print("🔍 [GraphQL] getConnections aufgerufen:")
        print("   originGlobalID: \(safeFrom)")
        print("   destinationGlobalID: \(safeTo)")
        print("   \(timeArgument)")
        #endif

        let query = """
        {
          trips(
            originGlobalID: "\(safeFrom)"
            destinationGlobalID: "\(safeTo)"
            \(timeArgument)
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
                legIntermediates {
                  point {
                    ... on StopPoint {
                      stopPointName
                    }
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

            #if DEBUG
            if let rawResponse = String(data: data, encoding: .utf8) {
                let preview = rawResponse.prefix(500)
                print("📦 [GraphQL] fetchTrips Antwort (\(data.count) bytes): \(preview)")
            }
            #endif

            if let gqlError = extractGraphQLErrors(from: data) {
                #if DEBUG
                print("❌ [GraphQL] Fehler in Antwort: \(gqlError.message)")
                #endif
                throw GraphQLError(message: gqlError.message)
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseData = json["data"] as? [String: Any],
               let trips = responseData["trips"] as? [[String: Any]] {
                #if DEBUG
                print("🚆 [GraphQL] \(trips.count) Trips gefunden")
                #endif

                let newTrips = trips.compactMap { trip -> DetailedTrip? in
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

                            let rawIntermediates = leg["legIntermediates"] as? [[String: Any]] ?? []
                            let parsedIntermediates: [IntermediateStop] = rawIntermediates.compactMap { intermediate in
                                guard let point = intermediate["point"] as? [String: Any],
                                      let name = point["stopPointName"] as? String
                                else { return nil }
                                return IntermediateStop(
                                    name: name,
                                    scheduledTime: "",
                                    estimatedTime: nil,
                                    occupancy: nil,
                                    latitude: nil,
                                    longitude: nil
                                )
                            }

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
                                destinationLabel: service["destinationLabel"] as? String,
                                intermediateStops: parsedIntermediates,
                                boardRef: boardPoint?["ref"] as? String
                            )
                        } else if let legMode = leg["mode"] as? String {
                            return TripLeg(
                                type: legMode == "WALK" ? .continuousLeg : .interchangeLeg,
                                mode: legMode,
                                boardStopName: nil,
                                alightStopName: nil,
                                departureTime: nil,
                                arrivalTime: nil,
                                estimatedDepartureTime: nil,
                                estimatedArrivalTime: nil,
                                serviceType: nil,
                                serviceName: legMode == "WALK" ? "Fußweg" : "Umstieg",
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
                return newTrips
            }
        }
        lastError = GraphQLError(message: "Fehler beim Laden der Verbindungen")
        return []
    }

    // MARK: - Departures
    // The RNV API has no native departures endpoint.
    // We discover departures by querying trips to major hubs and extracting the first timed leg.

    struct DeparturesResult {
        let departures: [Departure]
        let error: String?
    }

    private static var cachedHubIDs: [String] = []
    private static var cachedHubIDsDate: Date?
    private static let hubIDsCacheTTL: TimeInterval = 86400 // 24h

    func getDepartures(station: Station, accessToken: String, time: String? = nil) async -> DeparturesResult {
        let searchTime = time ?? ISO8601DateFormatter().string(from: Date())

        // Primär: native journeys-API mit Auslastung (erfordert hafasID)
        if !station.hafasID.isEmpty {
            let journeysResult = await getDeparturesViaJourneys(hafasID: station.hafasID, accessToken: accessToken, time: searchTime)
            if !journeysResult.departures.isEmpty {
                return journeysResult
            }
        }

        // Fallback: hub-workaround (wenn journeys keine Daten liefert)
        let cacheExpired = Self.cachedHubIDsDate.map { Date().timeIntervalSince($0) > Self.hubIDsCacheTTL } ?? true
        if Self.cachedHubIDs.isEmpty || cacheExpired {
            await resolveHubIDs(accessToken: accessToken)
        }

        let hubs = Self.cachedHubIDs.filter { $0 != station.globalID }
        guard !hubs.isEmpty else {
            return DeparturesResult(departures: [], error: "Abfahrtstafel nicht verfügbar")
        }

        var allDepartures: [Departure] = []

        for hubID in hubs.prefix(3) {
            let deps = await fetchFirstLegsAsDepartures(from: station.globalID, to: hubID, time: searchTime, accessToken: accessToken)
            allDepartures.append(contentsOf: deps)
        }

        var seen = Set<String>()
        var result = allDepartures.filter { seen.insert("\($0.lineName)-\($0.scheduledDeparture)").inserted }
        result.sort {
            let fmt = DateFormattingHelper.shared
            guard let a = fmt.parseISO8601($0.scheduledDeparture),
                  let b = fmt.parseISO8601($1.scheduledDeparture) else { return false }
            return a < b
        }

        return DeparturesResult(departures: result, error: result.isEmpty ? "Keine Abfahrten gefunden" : nil)
    }

    /// Kompatibilitäts-Überladung für Watch-Connectivity (hat nur globalID, kein hafasID)
    func getDepartures(globalID: String, accessToken: String, time: String? = nil) async -> DeparturesResult {
        let station = Station(hafasID: "", globalID: globalID, longName: "")
        return await getDepartures(station: station, accessToken: accessToken, time: time)
    }

    private func resolveHubIDs(accessToken: String) async {
        let hubNames = ["Mannheim Hauptbahnhof", "Heidelberg Hauptbahnhof", "Paradeplatz"]
        var ids: [String] = []
        for name in hubNames {
            if let station = await silentSearchStation(name: name, accessToken: accessToken) {
                ids.append(station.globalID)
            }
        }
        Self.cachedHubIDs = ids
        Self.cachedHubIDsDate = Date()
    }

    private func silentSearchStation(name: String, accessToken: String) async -> Station? {
        let safeName = sanitize(name)
        let query = """
        {
          stations(first: 1, name: "\(safeName)") {
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
        guard let data = try? await executeQuery(query: query, accessToken: accessToken),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = json["data"] as? [String: Any],
              let stationsObj = responseData["stations"] as? [String: Any],
              let elements = stationsObj["elements"] as? [[String: Any]],
              let first = elements.first,
              let hafasID = first["hafasID"] as? String,
              let globalID = first["globalID"] as? String,
              let longName = first["longName"] as? String
        else { return nil }
        return Station(hafasID: hafasID, globalID: globalID, longName: longName)
    }

    private func fetchFirstLegsAsDepartures(from originID: String, to destID: String, time: String, accessToken: String) async -> [Departure] {
        let query = """
        {
          trips(
            originGlobalID: "\(sanitize(originID))"
            destinationGlobalID: "\(sanitize(destID))"
            departureTime: "\(sanitize(time))"
          ) {
            legs {
              ... on TimedLeg {
                board {
                  point {
                    ... on StopPoint {
                      stopPointName
                    }
                  }
                  timetabledTime { isoString }
                  estimatedTime { isoString }
                }
                alight {
                  point {
                    ... on StopPoint {
                      stopPointName
                    }
                  }
                  timetabledTime { isoString }
                  estimatedTime { isoString }
                }
                legIntermediates {
                  point {
                    ... on StopPoint {
                      stopPointName
                    }
                  }
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

        guard let data = try? await executeQuery(query: query, accessToken: accessToken),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = json["data"] as? [String: Any],
              let trips = responseData["trips"] as? [[String: Any]]
        else { return [] }

        return trips.compactMap { trip -> Departure? in
            guard let legs = trip["legs"] as? [[String: Any]],
                  let firstTimedLeg = legs.first(where: { $0["board"] != nil }),
                  let board = firstTimedLeg["board"] as? [String: Any],
                  let service = firstTimedLeg["service"] as? [String: Any],
                  let lineName = service["name"] as? String,
                  let direction = service["destinationLabel"] as? String,
                  let timetabled = (board["timetabledTime"] as? [String: Any])?["isoString"] as? String,
                  timetabled != "null", !timetabled.isEmpty
            else { return nil }

            let estimated = (board["estimatedTime"] as? [String: Any])?["isoString"] as? String
            let rawBoardStop = (board["point"] as? [String: Any])?["stopPointName"] as? String
            let boardStopName: String? = (rawBoardStop == "null" || rawBoardStop?.isEmpty == true) ? nil : rawBoardStop

            let alight = firstTimedLeg["alight"] as? [String: Any]
            let rawAlightName = (alight?["point"] as? [String: Any])?["stopPointName"] as? String
            let alightName: String? = (rawAlightName == "null" || rawAlightName?.isEmpty == true) ? nil : rawAlightName
            let alightTimetabled = (alight?["timetabledTime"] as? [String: Any])?["isoString"] as? String
            let alightEstimated = (alight?["estimatedTime"] as? [String: Any])?["isoString"] as? String
            let finalStop = alightName.map {
                DepartureStop(
                    name: $0,
                    scheduledTime: (alightTimetabled == "null") ? nil : alightTimetabled,
                    estimatedTime: (alightEstimated == "null") ? nil : alightEstimated
                )
            }

            let rawIntermediates = firstTimedLeg["legIntermediates"] as? [[String: Any]] ?? []
            let intermediateStops: [DepartureStop] = rawIntermediates.compactMap { stop in
                guard let point = stop["point"] as? [String: Any],
                      let name = point["stopPointName"] as? String,
                      name != "null", !name.isEmpty else { return nil }
                return DepartureStop(name: name, scheduledTime: nil, estimatedTime: nil)
            }

            return Departure(
                scheduledDeparture: timetabled,
                estimatedDeparture: (estimated == "null") ? nil : estimated,
                lineName: lineName,
                direction: direction,
                serviceType: service["type"] as? String,
                boardStopName: boardStopName,
                intermediateStops: intermediateStops,
                finalStop: finalStop,
                originGlobalID: originID
            )
        }
    }

    // MARK: - Full Departure Route

    /// Fetches all intermediate stops and the final stop of a departure all the way to its terminus.
    /// Falls back to an empty result if the terminus station cannot be resolved or the trip is not found.
    func fetchFullDepartureRoute(
        originID: String,
        direction: String,
        lineName: String,
        scheduledDeparture: String,
        accessToken: String
    ) async -> (intermediates: [DepartureStop], finalStop: DepartureStop?) {
        guard let terminus = await silentSearchStation(name: direction, accessToken: accessToken) else {
            return ([], nil)
        }
        let deps = await fetchFirstLegsAsDepartures(
            from: originID,
            to: terminus.globalID,
            time: scheduledDeparture,
            accessToken: accessToken
        )
        guard let match = deps.first(where: { $0.lineName == lineName }) else {
            return ([], nil)
        }
        return (match.intermediateStops, match.finalStop)
    }

    // MARK: - Live Updates

    func getLiveTripUpdates(tripId: String, accessToken: String) async -> DetailedTrip? {
        #if DEBUG
        print("🔄 [GraphQL] Rufe Live-Updates ab für Trip: \(tripId)")
        print("⚠️ [GraphQL] Live-Update API noch nicht implementiert")
        #endif
        return nil
    }

    // MARK: - Departures via station(id).journeys (native API mit Auslastung)

    func getDeparturesViaJourneys(hafasID: String, accessToken: String, time: String) async -> DeparturesResult {
        let safeID = sanitize(hafasID)
        let safeTime = sanitize(time)

        let query = """
        {
          station(id: "\(safeID)") {
            journeys(startTime: "\(safeTime)", first: 30) {
              elements {
                ... on Journey {
                  id
                  line {
                    id
                  }
                  loads(onlyHafasID: "\(safeID)") {
                    loadType
                    ratio
                  }
                  stops(onlyHafasID: "\(safeID)") {
                    plannedDeparture {
                      isoString
                    }
                    realtimeDeparture {
                      isoString
                    }
                  }
                  destination {
                    ... on StopPoint {
                      stopPointName
                    }
                  }
                }
              }
            }
          }
        }
        """

        guard let data = try? await executeQuery(query: query, accessToken: accessToken) else {
            return DeparturesResult(departures: [], error: "Netzwerkfehler")
        }

        if let gqlError = extractGraphQLErrors(from: data) {
            return DeparturesResult(departures: [], error: gqlError.message)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = json["data"] as? [String: Any],
              let stationObj = responseData["station"] as? [String: Any],
              let journeysObj = stationObj["journeys"] as? [String: Any],
              let elements = journeysObj["elements"] as? [[String: Any]]
        else {
            return DeparturesResult(departures: [], error: "Keine Daten")
        }

        let departures: [Departure] = elements.compactMap { element -> Departure? in
            guard let lineObj = element["line"] as? [String: Any],
                  let lineID = lineObj["id"] as? String,
                  let stopsArr = element["stops"] as? [[String: Any]],
                  let firstStop = stopsArr.first,
                  let plannedObj = firstStop["plannedDeparture"] as? [String: Any],
                  let planned = plannedObj["isoString"] as? String,
                  planned != "null", !planned.isEmpty
            else { return nil }

            let realtime = (firstStop["realtimeDeparture"] as? [String: Any])?["isoString"] as? String
            let effectiveRealtime = (realtime == "null" || realtime?.isEmpty == true) ? nil : realtime

            // line.id Format: "rnv:64:H" oder "rnv:S1:H" → letztes Segment vor ":H" oder zweiter Teil
            let lineName = lineID.split(separator: ":").dropFirst().first.map(String.init) ?? lineID

            let destinationName: String
            if let destObj = element["destination"] as? [String: Any],
               let name = destObj["stopPointName"] as? String, name != "null" {
                destinationName = name
            } else {
                destinationName = ""
            }

            // Auslastung
            var occupancy: OccupancyLevel? = nil
            if let loadsArr = element["loads"] as? [[String: Any]],
               let firstLoad = loadsArr.first,
               let loadType = firstLoad["loadType"] as? String {
                occupancy = OccupancyLevel(from: loadType)
            }

            return Departure(
                scheduledDeparture: planned,
                estimatedDeparture: effectiveRealtime,
                lineName: lineName,
                direction: destinationName,
                serviceType: nil,
                occupancy: occupancy
            )
        }

        return DeparturesResult(
            departures: departures,
            error: departures.isEmpty ? "Keine Abfahrten gefunden" : nil
        )
    }

    // MARK: - Occupancy Enrichment für Verbindungen

    func enrichConnectionsWithOccupancy(accessToken: String) async {
        let trips = detailedTrips
        guard !trips.isEmpty else { return }

        // Sammle unique (hafasID, departureTime) Paare aus allen TimedLegs
        struct LookupKey: Hashable {
            let hafasID: String
            let depTime: String
        }

        var stationTimeToJourneys: [String: [[String: Any]]] = [:]

        // Extrahiere hafasIDs aus boardRef (Format: "de:08222:2417:..." → "2417")
        var uniqueStationTimes: [(hafasID: String, depTime: String)] = []
        for trip in trips {
            for leg in trip.legs where leg.isTimedLeg {
                guard let ref = leg.boardRef,
                      let depTime = leg.departureTime else { continue }
                let parts = ref.split(separator: ":")
                guard parts.count >= 3 else { continue }
                let hafasID = String(parts[2])
                if !uniqueStationTimes.contains(where: { $0.hafasID == hafasID && $0.depTime == depTime }) {
                    uniqueStationTimes.append((hafasID, depTime))
                }
            }
        }

        // Query journeys pro unique Station/Zeit
        for (hafasID, depTime) in uniqueStationTimes {
            let safeID = sanitize(hafasID)
            let safeTime = sanitize(depTime)
            let query = """
            {
              station(id: "\(safeID)") {
                journeys(startTime: "\(safeTime)", first: 10) {
                  elements {
                    ... on Journey {
                      line { id }
                      loads(onlyHafasID: "\(safeID)") {
                        loadType
                        ratio
                      }
                      stops(onlyHafasID: "\(safeID)") {
                        plannedDeparture { isoString }
                      }
                    }
                  }
                }
              }
            }
            """
            guard let data = try? await executeQuery(query: query, accessToken: accessToken),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = json["data"] as? [String: Any],
                  let stationObj = responseData["station"] as? [String: Any],
                  let journeysObj = stationObj["journeys"] as? [String: Any],
                  let elements = journeysObj["elements"] as? [[String: Any]]
            else { continue }

            stationTimeToJourneys["\(hafasID)|\(depTime)"] = elements
        }

        // Anreichern der Trips
        var enriched = trips
        for tripIdx in enriched.indices {
            var legs = enriched[tripIdx].legs
            for legIdx in legs.indices {
                var leg = legs[legIdx]
                guard leg.isTimedLeg,
                      let ref = leg.boardRef,
                      let depTime = leg.departureTime,
                      leg.occupancy == nil
                else { continue }

                let parts = ref.split(separator: ":")
                guard parts.count >= 3 else { continue }
                let hafasID = String(parts[2])

                guard let journeys = stationTimeToJourneys["\(hafasID)|\(depTime)"] else { continue }

                // Matche Journey an Leg über Linienname und Zeit
                for journey in journeys {
                    guard let lineObj = journey["line"] as? [String: Any],
                          let lineID = lineObj["id"] as? String else { continue }

                    // lineName aus leg (z.B. "64"), lineID z.B. "rnv:64:H"
                    let journeyLineName = lineID.split(separator: ":").dropFirst().first.map(String.init) ?? lineID
                    guard journeyLineName == (leg.serviceName ?? "") else { continue }

                    // Zeitabgleich: Journey plannedDeparture ≈ leg.departureTime
                    if let stopsArr = journey["stops"] as? [[String: Any]],
                       let firstStop = stopsArr.first,
                       let plannedObj = firstStop["plannedDeparture"] as? [String: Any],
                       let planned = plannedObj["isoString"] as? String,
                       abs(isoTimeDiff(planned, depTime)) > 120 {
                        continue
                    }

                    if let loadsArr = journey["loads"] as? [[String: Any]],
                       let firstLoad = loadsArr.first,
                       let loadType = firstLoad["loadType"] as? String {
                        leg.occupancy = OccupancyLevel(from: loadType)
                    }
                    break
                }
                legs[legIdx] = leg
            }
            // DetailedTrip ist ein Struct – neues Exemplar mit aktualisierten Legs erstellen
            enriched[tripIdx] = DetailedTrip(
                startTime: enriched[tripIdx].startTime,
                endTime: enriched[tripIdx].endTime,
                interchanges: enriched[tripIdx].interchanges,
                legs: legs
            )
        }

        detailedTrips = enriched
    }

    // Sekunden-Differenz zwischen zwei ISO-8601-Strings (|a - b|)
    private func isoTimeDiff(_ a: String, _ b: String) -> Double {
        let fmt = DateFormattingHelper.shared
        guard let da = fmt.parseISO8601(a), let db = fmt.parseISO8601(b) else { return Double.infinity }
        return da.timeIntervalSince(db)
    }
}
