// Datenmodelle für die Watch App – spiegeln die Codable-Typen aus der iPhone App.

import Foundation
import SwiftUI

// MARK: - Gespeicherte Trips (aus "savedTripData" im App Group, gesetzt vom LiveActivityManager)

struct WidgetTripData: Codable, Identifiable {
    let id: String
    let startTime: String
    let endTime: String
    let interchanges: Int
    let startStation: String
    let endStation: String
    let legs: [WidgetTripLegData]
}

struct WidgetTripLegData: Codable {
    let legType: String?
    let boardStopName: String?
    let alightStopName: String?
    let departureTime: String?
    let arrivalTime: String?
    let serviceName: String?
    let serviceType: String?
    let destinationLabel: String?

    var isTimedLeg: Bool { legType == "timedLeg" }
}

// MARK: - Geplante Trips (aus "plannedTripData" im App Group)

struct TripData: Codable, Identifiable {
    let id: String
    let startTime: String
    let endTime: String
    let interchanges: Int
    let startStation: String
    let endStation: String
    let legs: [TripLegData]
}

struct TripLegData: Codable {
    let legType: String?
    let boardStopName: String?
    let alightStopName: String?
    let departureTime: String?
    let arrivalTime: String?
    let serviceName: String?
    let serviceType: String?
    let destinationLabel: String?
    let intermediateStopNames: [String]?

    var isTimedLeg: Bool { legType == "timedLeg" }
}

// MARK: - Abfahrten (kommen via WatchConnectivity vom iPhone)

struct WatchDeparture: Identifiable, Codable {
    let id: String
    let lineName: String
    let direction: String
    let scheduledTime: String
    let estimatedTime: String?
    let serviceType: String?
    let delayMinutes: Int?
}

// MARK: - Trip Phase

enum TripPhase: String, Codable {
    case beforeDeparture
    case duringJourney
    case arrived
}

// MARK: - Datum-Helfer

struct WatchDateHelper {

    private static let withFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let withoutFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone.current
        return f
    }()

    static func parse(_ iso: String) -> Date? {
        withFrac.date(from: iso) ?? withoutFrac.date(from: iso)
    }

    static func formatTime(_ iso: String) -> String {
        guard let d = parse(iso) else { return "--:--" }
        return timeFmt.string(from: d)
    }

    static func minutesUntil(_ iso: String) -> Int? {
        guard let d = parse(iso) else { return nil }
        let secs = d.timeIntervalSinceNow
        guard secs > 0 else { return nil }
        return Int(secs / 60)
    }

    static func durationString(start: String, end: String) -> String {
        guard let s = parse(start), let e = parse(end) else { return "?" }
        let mins = Int(e.timeIntervalSince(s) / 60)
        return "\(mins) min"
    }

    static func phase(for trip: WidgetTripData) -> TripPhase {
        let now = Date()
        if let dep = parse(trip.startTime), dep > now { return .beforeDeparture }
        if let arr = parse(trip.endTime), arr <= now { return .arrived }
        return .duringJourney
    }

    static func phase(for trip: TripData) -> TripPhase {
        let now = Date()
        if let dep = parse(trip.startTime), dep > now { return .beforeDeparture }
        if let arr = parse(trip.endTime), arr <= now { return .arrived }
        return .duringJourney
    }
}

// MARK: - Stil-Helfer

struct WatchStyleHelper {

    static func colorValue(serviceType: String?, serviceName: String?) -> Color {
        let t = (serviceType ?? "").uppercased()
        let n = (serviceName ?? "").uppercased().trimmingCharacters(in: .whitespaces)

        if isSBahn(t, n) { return .green }
        if isLongDistance(t, n) { return Color(white: 0.35) }
        if isRegional(t, n) { return Color(red: 0.4, green: 0.1, blue: 0.6) }
        if t.contains("STRASSENBAHN") || t.contains("TRAM") { return .red }
        if t.contains("BUS") { return .blue }
        return .gray
    }

    static func icon(serviceType: String?, serviceName: String?) -> String {
        let t = (serviceType ?? "").uppercased()
        let n = (serviceName ?? "").uppercased().trimmingCharacters(in: .whitespaces)

        if isSBahn(t, n) { return "train.side.front.car" }
        if isLongDistance(t, n) { return "train.side.front.car" }
        if isRegional(t, n) { return "tram.fill" }
        if t.contains("STRASSENBAHN") || t.contains("TRAM") { return "lightrail.fill" }
        if t.contains("BUS") { return "bus.fill" }
        return "tram.fill"
    }

    static func shortName(_ name: String?) -> String {
        (name ?? "?")
            .replacingOccurrences(of: "RNV ", with: "")
            .replacingOccurrences(of: "rnv ", with: "")
            .replacingOccurrences(of: "Linie ", with: "")
    }

    private static func isSBahn(_ t: String, _ n: String) -> Bool {
        if t.contains("S_BAHN") || t.contains("SBAHN") || t.contains("SUBURBAN") { return true }
        return n.count >= 2 && n.hasPrefix("S") && n.dropFirst().first?.isNumber == true
    }

    private static func isLongDistance(_ t: String, _ n: String) -> Bool {
        if t.contains("ICE") || t.contains("INTERCITY") || t.contains("FERNVERKEHR") { return true }
        return n.hasPrefix("ICE") || n.hasPrefix("IC") || n.hasPrefix("EC")
    }

    private static func isRegional(_ t: String, _ n: String) -> Bool {
        if t.contains("REGIONAL") || t.contains("_RE") || t.contains("RB") || t.contains("MEX") { return true }
        return n.hasPrefix("RE") || n.hasPrefix("RB") || n.hasPrefix("MEX")
    }
}
