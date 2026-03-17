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
    static func getColor(for serviceType: String) -> Color {
        switch serviceType {
        case "STRASSENBAHN": return .red
        case "BUS": return .blue
        case "S_BAHN": return .green
        default: return .gray
        }
    }

    static func getIcon(for serviceType: String) -> String {
        switch serviceType {
        case "STRASSENBAHN": return "tram.fill"
        case "BUS": return "bus.fill"
        case "S_BAHN": return "train.side.front.car"
        default: return "questionmark"
        }
    }

    static func getShortName(from serviceName: String) -> String {
        serviceName.replacingOccurrences(of: "RNV ", with: "")
    }
}