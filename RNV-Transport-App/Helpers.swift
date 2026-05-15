//
//  Helpers.swift
//  RNV-Transport-App
//
//  Zusammengeführt aus DateFormattingHelper.swift + TransportIconHelper.swift
//

import Foundation
import SwiftUI
import UIKit

// MARK: - DateFormattingHelper

final class DateFormattingHelper: @unchecked Sendable {
    static let shared = DateFormattingHelper()

    private let lock = NSLock()

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
        lock.lock()
        defer { lock.unlock() }
        return timeFormatter.string(from: date)
    }

    func formatTimeFromDate(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return timeFormatter.string(from: date)
    }

    func formatDate(_ isoString: String) -> String {
        guard let date = parseISO8601(isoString) else { return isoString }
        lock.lock()
        defer { lock.unlock() }
        return dateFormatter.string(from: date)
    }

    func formatDateTime(_ isoString: String) -> String {
        guard let date = parseISO8601(isoString) else { return isoString }
        lock.lock()
        defer { lock.unlock() }
        return fullDateTimeFormatter.string(from: date)
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EE, d. MMM"
        return f
    }()

    func formatDateShort(_ date: Date) -> String {
        return Self.shortDateFormatter.string(from: date)
    }

    private let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    func formatFullDate(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return fullDateFormatter.string(from: date)
    }

    func parseGermanDate(_ raw: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        for format in ["dd.MM.yyyy", "dd/MM/yyyy"] {
            fullDateFormatter.dateFormat = format
            if let d = fullDateFormatter.date(from: raw) {
                fullDateFormatter.dateFormat = "dd.MM.yyyy"
                return d
            }
        }
        return nil
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
    /// Prüft, ob ein Leg eine S-Bahn ist – anhand serviceType ODER serviceName (z. B. "S1", "S3")
    static func isSBahnLine(serviceType: String?, serviceName: String?) -> Bool {
        let type = (serviceType ?? "").uppercased()
        if type.contains("S_BAHN") || type.contains("SBAHN") || type.contains("SUBURBAN") {
            return true
        }
        // Fallback: Linienname beginnt mit "S" gefolgt von einer Ziffer (z. B. S1, S3, S33)
        let name = (serviceName ?? "").trimmingCharacters(in: .whitespaces)
        if name.count >= 2,
           name.uppercased().first == "S",
           let secondChar = name.dropFirst().first,
           secondChar.isNumber {
            return true
        }
        return false
    }

    /// Prüft, ob ein Leg ein Regionalzug ist – anhand serviceType ODER serviceName (z. B. "RE10a", "RB40", "MEX12")
    static func isRegionalLine(serviceType: String?, serviceName: String?) -> Bool {
        let type = (serviceType ?? "").uppercased()
        if type.contains("REGIONAL") || type.contains("_RE") || type.contains("RB") || type.contains("MEX") {
            return true
        }
        // Fallback: Linienname beginnt mit "RE" oder "RB" gefolgt von einer Ziffer
        let name = (serviceName ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        if name.count >= 3,
           (name.hasPrefix("RE") || name.hasPrefix("RB")),
           let digitChar = name.dropFirst(2).first,
           digitChar.isNumber {
            return true
        }
        // MEX-Sonderfall: Präfix ist 3 Zeichen lang (z. B. "MEX12", "MEX16a")
        if name.count >= 4,
           name.hasPrefix("MEX"),
           let digitChar = name.dropFirst(3).first,
           digitChar.isNumber {
            return true
        }
        return false
    }

    /// Prüft, ob ein Leg ein Fernverkehrszug ist (ICE, IC, EC, TGV, RJX, FLX)
    static func isLongDistanceLine(serviceType: String?, serviceName: String?) -> Bool {
        let type = (serviceType ?? "").uppercased()
        if type.contains("ICE") || type.contains("INTERCITY") || type.contains("FERNVERKEHR") || type.contains("HOCHGESCHWINDIGKEIT") {
            return true
        }
        let name = (serviceName ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        // ICE vor IC prüfen, da "IC".hasPrefix auch auf "ICE" matchen würde
        if name.hasPrefix("ICE") || name.hasPrefix("EC") || name.hasPrefix("TGV") || name.hasPrefix("RJX") || name.hasPrefix("FLX") || name.hasPrefix("IC") {
            return true
        }
        return false
    }

    static func getLineColor(for serviceType: String?, serviceName: String? = nil) -> Color {
        let normalized = getShortLineName(from: serviceName).uppercased()

        switch normalized {
        case "1":           return Color(hex: "#f39b9a")
        case "3":           return Color(hex: "#d6ad00")
        case "4", "4A":     return Color(hex: "#e30613")
        case "5", "5A":     return Color(hex: "#00975f")
        case "6":           return Color(hex: "#956c29")
        case "7":           return Color(hex: "#fecc00")
        case "60":          return Color(hex: "#4e2583")
        case "61":          return Color(hex: "#4a96d1")
        default: break
        }

        if isLongDistanceLine(serviceType: serviceType, serviceName: serviceName) {
            return Color(hex: "#4a96d1")
        }
        if isSBahnLine(serviceType: serviceType, serviceName: serviceName) {
            return Color(hex: "#00975f")
        }
        if isRegionalLine(serviceType: serviceType, serviceName: serviceName) {
            return Color(hex: "#4e2583")
        }

        let type = (serviceType ?? "").uppercased()
        if type.contains("STRASSENBAHN") || type.contains("TRAM") {
            return Color(hex: "#e30613")
        } else if type.contains("BUS") {
            return Color(hex: "#4a96d1")
        }
        return Color(hex: "#292524")
    }

    static func getTransportIcon(for serviceType: String?, serviceName: String? = nil) -> String {
        if isSBahnLine(serviceType: serviceType, serviceName: serviceName) {
            return "s.circle.fill"
        }
        if isLongDistanceLine(serviceType: serviceType, serviceName: serviceName) {
            return "train.side.front.car"
        }
        if isRegionalLine(serviceType: serviceType, serviceName: serviceName) {
            return "tram.fill"
        }
        let type = (serviceType ?? "").uppercased()
        if type.contains("STRASSENBAHN") || type.contains("TRAM") {
            return "lightrail.fill"
        } else if type.contains("BUS") {
            return "bus.fill"
        }
        return "questionmark"
    }

    /// Entfernt Präfixe aus Liniennamen für kompaktere Darstellung
    static func getShortLineName(from serviceName: String?) -> String {
        guard let name = serviceName else { return "?" }
        return name
            .replacingOccurrences(of: "RNV ", with: "")
            .replacingOccurrences(of: "rnv ", with: "")
            .replacingOccurrences(of: "Linie ", with: "")
    }
}

// MARK: - ShareSheet (UIActivityViewController Wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - HapticHelper

struct HapticHelper {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
