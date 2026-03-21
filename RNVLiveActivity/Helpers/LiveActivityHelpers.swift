//
//  LiveActivityHelpers.swift
//  RNVLiveActivity
//
//  Created by Friedrich, Stefan on 21.01.26.
//

import SwiftUI

// MARK: - Date Calculation Helper

struct DateCalculationHelper {
    // MARK: - Shared ISO8601 Parsers

    private static let formatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let formatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Parsing

    static func parseDate(_ isoString: String) -> Date? {
        if let date = formatterWithFractionalSeconds.date(from: isoString) {
            return date
        }
        return formatterWithoutFractionalSeconds.date(from: isoString)
    }

    // MARK: - Departure Checks

    static func isBeforeDeparture(_ departureTimeISO: String, at currentTime: Date, delay: Int? = nil) -> Bool {
        guard let departureDate = parseDate(departureTimeISO) else { return false }
        let effectiveDepartureTime: Date
        if let delay = delay, delay > 0 {
            effectiveDepartureTime = departureDate.addingTimeInterval(TimeInterval(delay * 60))
        } else {
            effectiveDepartureTime = departureDate
        }
        return currentTime < effectiveDepartureTime
    }

    // MARK: - Timer Ranges (for SwiftUI Text(timerInterval:))

    static func safeCalculateDepartureDate(from isoString: String, currentTime: Date) -> ClosedRange<Date>? {
        guard let departureDate = parseDate(isoString),
              departureDate > currentTime else { return nil }
        return currentTime...departureDate
    }

    static func safeCalculateRealArrivalDate(from arrivalTimeISO: String, currentTime: Date) -> ClosedRange<Date>? {
        guard let arrivalDate = parseDate(arrivalTimeISO),
              arrivalDate > currentTime else { return nil }
        return currentTime...arrivalDate
    }

    static func safeCalculateEstimatedDepartureDate(from departureTimeISO: String, delayMinutes: Int, currentTime: Date) -> ClosedRange<Date>? {
        guard let departureDate = parseDate(departureTimeISO) else { return nil }
        let estimatedDepartureDate = departureDate.addingTimeInterval(TimeInterval(delayMinutes * 60))
        guard estimatedDepartureDate > currentTime else { return nil }
        return currentTime...estimatedDepartureDate
    }

    static func safeCalculateDelayedArrivalDate(from arrivalTimeISO: String, delayMinutes: Int, currentTime: Date) -> ClosedRange<Date>? {
        guard let arrivalDate = parseDate(arrivalTimeISO) else { return nil }
        let delayedArrivalDate = arrivalDate.addingTimeInterval(TimeInterval(delayMinutes * 60))
        guard delayedArrivalDate > currentTime else { return nil }
        return currentTime...delayedArrivalDate
    }
}

// MARK: - Style Helper

struct StyleHelper {
    // MARK: - Linientyp-Erkennung (serviceType + serviceName Fallback)

    private static func isSBahn(type: String, name: String) -> Bool {
        if type.contains("S_BAHN") || type.contains("SBAHN") || type.contains("SUBURBAN") { return true }
        if name.count >= 2, name.hasPrefix("S"), name.dropFirst().first?.isNumber == true { return true }
        return false
    }

    private static func isLongDistance(type: String, name: String) -> Bool {
        if type.contains("ICE") || type.contains("INTERCITY") || type.contains("FERNVERKEHR") || type.contains("HOCHGESCHWINDIGKEIT") { return true }
        if name.hasPrefix("ICE") || name.hasPrefix("IC") || name.hasPrefix("EC") || name.hasPrefix("TGV") || name.hasPrefix("RJX") || name.hasPrefix("FLX") { return true }
        return false
    }

    private static func isRegional(type: String, name: String) -> Bool {
        if type.contains("REGIONAL") || type.contains("_RE") || type.contains("RB") || type.contains("MEX") { return true }
        if name.count >= 3, (name.hasPrefix("RE") || name.hasPrefix("RB") || name.hasPrefix("MEX")), name.dropFirst(2).first?.isNumber == true { return true }
        // MEX-Sonderfall: Präfix ist 3 Zeichen lang
        if name.count >= 4, name.hasPrefix("MEX"), name.dropFirst(3).first?.isNumber == true { return true }
        return false
    }

    static func getColor(for serviceType: String, serviceName: String = "") -> Color {
        let type = serviceType.uppercased()
        let name = serviceName.trimmingCharacters(in: .whitespaces).uppercased()

        if isSBahn(type: type, name: name) { return .green }
        if isLongDistance(type: type, name: name) { return Color(red: 0.55, green: 0.0, blue: 0.05) }
        if isRegional(type: type, name: name) { return Color(red: 0.4, green: 0.1, blue: 0.6) }
        if type.contains("STRASSENBAHN") || type.contains("TRAM") { return .red }
        if type.contains("BUS") { return .blue }
        return .gray
    }

    static func getIcon(for serviceType: String, serviceName: String = "") -> String {
        let type = serviceType.uppercased()
        let name = serviceName.trimmingCharacters(in: .whitespaces).uppercased()

        if isSBahn(type: type, name: name) { return "s.circle.fill" }
        if isLongDistance(type: type, name: name) { return "train.side.front.car" }
        if isRegional(type: type, name: name) { return "tram.fill" }
        if type.contains("STRASSENBAHN") || type.contains("TRAM") { return "lightrail.fill" }
        if type.contains("BUS") { return "bus.fill" }
        return "questionmark"
    }

    static func getShortName(from serviceName: String) -> String {
        serviceName
            .replacingOccurrences(of: "RNV ", with: "")
            .replacingOccurrences(of: "rnv ", with: "")
            .replacingOccurrences(of: "Linie ", with: "")
    }
}
