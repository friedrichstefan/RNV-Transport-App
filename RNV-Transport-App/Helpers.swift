//
//  Helpers.swift
//  RNV-Transport-App
//
//  Zusammengeführt aus DateFormattingHelper.swift + TransportIconHelper.swift
//

import Foundation
import SwiftUI

// MARK: - DateFormattingHelper

class DateFormattingHelper {
    static let shared = DateFormattingHelper()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    private let fullDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601WithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Parsing

    func parseISO8601(_ isoString: String) -> Date? {
        if let date = Self.iso8601WithFractionalSeconds.date(from: isoString) {
            return date
        }
        return Self.iso8601WithoutFractionalSeconds.date(from: isoString)
    }

    // MARK: - Formatting

    func formatTime(_ isoString: String) -> String {
        guard let date = parseISO8601(isoString) else { return isoString }
        return timeFormatter.string(from: date)
    }

    func formatTimeFromDate(_ date: Date) -> String {
        return timeFormatter.string(from: date)
    }

    func formatDate(_ isoString: String) -> String {
        guard let date = parseISO8601(isoString) else { return isoString }
        return dateFormatter.string(from: date)
    }

    func formatDateTime(_ isoString: String) -> String {
        guard let date = parseISO8601(isoString) else { return isoString }
        return fullDateTimeFormatter.string(from: date)
    }

    func formatTimeRemaining(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(timeInterval))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return minutes > 0 ? String(format: "%d:%02d", minutes, seconds) : String(format: "0:%02d", seconds)
    }

    // MARK: - Delay Calculation

    func calculateDelay(timetabled: String, estimated: String?) -> Int? {
        guard let estimatedString = estimated else { return nil }

        guard let timetabledDate = parseISO8601(timetabled),
              let estimatedDate = parseISO8601(estimatedString) else {
            return nil
        }

        let delaySeconds = estimatedDate.timeIntervalSince(timetabledDate)
        let delayMinutes = Int(delaySeconds / 60)

        return delayMinutes > 0 ? delayMinutes : nil
    }

    // MARK: - Duration Calculation

    func calculateDuration(start: String, end: String) -> String {
        guard let startDate = parseISO8601(start),
              let endDate = parseISO8601(end) else { return "?" }

        let duration = endDate.timeIntervalSince(startDate)
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }

    // MARK: - Phase Detection

    func isBeforeDeparture(_ departureTimeISO: String, at currentTime: Date = Date()) -> Bool {
        guard let departureDate = parseISO8601(departureTimeISO) else { return false }
        return currentTime < departureDate
    }

    func isArrived(_ arrivalTimeISO: String, at currentTime: Date = Date()) -> Bool {
        guard let arrivalDate = parseISO8601(arrivalTimeISO) else { return false }
        return currentTime >= arrivalDate
    }
}

// MARK: - TransportIconHelper

struct TransportIconHelper {
    static func getLineColor(for serviceType: String?) -> Color {
        switch serviceType {
        case "STRASSENBAHN": return .red
        case "BUS": return .blue
        case "S_BAHN": return .green
        default: return .gray
        }
    }

    static func getTransportIcon(for serviceType: String?) -> String {
        switch serviceType {
        case "STRASSENBAHN": return "tram.fill"
        case "BUS": return "bus.fill"
        case "S_BAHN": return "train.side.front.car"
        default: return "questionmark"
        }
    }

    static func getShortLineName(from serviceName: String?) -> String {
        guard let name = serviceName else { return "?" }
        return name.replacingOccurrences(of: "RNV ", with: "")
    }
}