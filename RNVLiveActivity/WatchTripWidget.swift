//
//  WatchTripWidget.swift
//  RNVLiveActivity
//
//  Apple Watch Komplikationen für ÖPNV Mannheim & Umgebung
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct WatchTripEntry: TimelineEntry {
    let date: Date
    let trip: WidgetTripData?
    let isPlaceholder: Bool
}

// MARK: - Timeline Provider

struct WatchTripProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchTripEntry {
        WatchTripEntry(date: Date(), trip: nil, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchTripEntry) -> Void) {
        let trip = WidgetDataProvider.loadNextTrip()
        completion(WatchTripEntry(date: Date(), trip: trip, isPlaceholder: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchTripEntry>) -> Void) {
        let trip = WidgetDataProvider.loadNextTrip()
        let now = Date()
        var entries: [WatchTripEntry] = []
        for i in 0..<15 {
            let entryDate = now.addingTimeInterval(Double(i) * 60)
            entries.append(WatchTripEntry(date: entryDate, trip: trip, isPlaceholder: false))
        }
        let nextRefresh = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }
}

// MARK: - Widget Definition

struct WatchTripWidget: Widget {
    let kind = "WatchTripWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchTripProvider()) { entry in
            WatchTripWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "rnv://watch/active-trip"))
        }
        .configurationDisplayName("Nächste Fahrt")
        .description("Zeigt deine nächste ÖPNV-Verbindung.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}

// MARK: - Entry View Router

struct WatchTripWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchTripEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            WatchRectangularView(entry: entry)
        case .accessoryCircular:
            WatchCircularView(entry: entry)
        case .accessoryInline:
            WatchInlineView(entry: entry)
        default:
            WatchRectangularView(entry: entry)
        }
    }
}

// MARK: - Accessory Rectangular

struct WatchRectangularView: View {
    let entry: WatchTripEntry

    var body: some View {
        if entry.isPlaceholder {
            placeholderView
        } else if let trip = entry.trip {
            tripView(trip)
        } else {
            emptyView
        }
    }

    private var placeholderView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 36, height: 14)
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 28, height: 14)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(.secondary.opacity(0.2))
                .frame(height: 10)
            RoundedRectangle(cornerRadius: 2)
                .fill(.secondary.opacity(0.15))
                .frame(height: 10)
        }
    }

    private func tripView(_ trip: WidgetTripData) -> some View {
        let firstLeg = trip.legs.first(where: { $0.isTimedLeg })
        let departureDate = WidgetDataProvider.parseISO8601(trip.startTime)
        let arrivalDate = WidgetDataProvider.parseISO8601(trip.endTime)
        let isBeforeDeparture = departureDate.map { $0 > entry.date } ?? false
        let isArrived = arrivalDate.map { $0 <= entry.date } ?? false

        return VStack(alignment: .leading, spacing: 2) {
            // Row 1: Line badge + countdown / status
            HStack(spacing: 4) {
                // Line icon + name
                if let leg = firstLeg {
                    HStack(spacing: 2) {
                        Image(systemName: watchLineIcon(for: leg.serviceType, serviceName: leg.serviceName))
                            .font(.system(size: 9, weight: .bold))
                        Text(watchShortName(from: leg.serviceName))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(watchLineColor(for: leg.serviceType, serviceName: leg.serviceName))
                    )
                }

                Spacer(minLength: 2)

                // Status / Countdown
                if isArrived {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                        Text("Da")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.green)
                } else if isBeforeDeparture, let depDate = departureDate {
                    let mins = max(0, Int(depDate.timeIntervalSince(entry.date) / 60))
                    if mins == 0 {
                        Text("Jetzt")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.green)
                    } else {
                        Text("in \(mins)'")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.cyan)
                    }
                } else {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(.green)
                            .frame(width: 4, height: 4)
                        Text("Fährt")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                }
            }

            // Row 2: Times
            HStack(spacing: 3) {
                Text(WidgetDataProvider.formatTime(trip.startTime))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)

                Image(systemName: "arrow.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.secondary)

                Text(WidgetDataProvider.formatTime(trip.endTime))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer(minLength: 2)

                Text(WidgetDataProvider.calculateDuration(start: trip.startTime, end: trip.endTime))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Row 3: Route
            HStack(spacing: 3) {
                Circle()
                    .fill(.green)
                    .frame(width: 4, height: 4)

                Text(trip.startStation)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.secondary)

                Text(trip.endStation)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .widgetAccentable()
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("ÖPNV")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Text("Keine aktive Fahrt")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))

            Text("Starte Verfolgung in der App")
                .font(.system(size: 9, weight: .regular))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}

// MARK: - Accessory Circular

struct WatchCircularView: View {
    let entry: WatchTripEntry

    var body: some View {
        if entry.isPlaceholder {
            placeholderView
        } else if let trip = entry.trip {
            tripView(trip)
        } else {
            emptyView
        }
    }

    private var placeholderView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "tram.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary.opacity(0.4))
        }
    }

    private func tripView(_ trip: WidgetTripData) -> some View {
        let firstLeg = trip.legs.first(where: { $0.isTimedLeg })
        let departureDate = WidgetDataProvider.parseISO8601(trip.startTime)
        let arrivalDate = WidgetDataProvider.parseISO8601(trip.endTime)
        let isBeforeDeparture = departureDate.map { $0 > entry.date } ?? false
        let isArrived = arrivalDate.map { $0 <= entry.date } ?? false

        return ZStack {
            AccessoryWidgetBackground()

            if isArrived {
                // Arrived state
                VStack(spacing: 1) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.green)
                    Text("Da!")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundColor(.green)
                }
            } else if isBeforeDeparture, let depDate = departureDate {
                // Countdown state
                let mins = max(0, Int(depDate.timeIntervalSince(entry.date) / 60))
                VStack(spacing: 0) {
                    // Line icon
                    if let leg = firstLeg {
                        Image(systemName: watchLineIcon(for: leg.serviceType, serviceName: leg.serviceName))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                    } else {
                        Image(systemName: "tram.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                    }

                    if mins == 0 {
                        Text("Jetzt")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(.green)
                    } else {
                        Text("\(mins)")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Min")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // During journey
                VStack(spacing: 1) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)

                    // Show arrival time
                    Text(WidgetDataProvider.formatTime(trip.endTime))
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(.primary)

                    Text("Ank.")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
        }
        .widgetAccentable()
    }

    private var emptyView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("ÖPNV")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }
}

// MARK: - Accessory Inline

struct WatchInlineView: View {
    let entry: WatchTripEntry

    var body: some View {
        if let trip = entry.trip {
            tripInlineView(trip)
        } else {
            Text(Image(systemName: "tram.fill")) + Text(" Keine Fahrt")
        }
    }

    private func tripInlineView(_ trip: WidgetTripData) -> some View {
        let firstLeg = trip.legs.first(where: { $0.isTimedLeg })
        let departureDate = WidgetDataProvider.parseISO8601(trip.startTime)
        let arrivalDate = WidgetDataProvider.parseISO8601(trip.endTime)
        let isBeforeDeparture = departureDate.map { $0 > entry.date } ?? false
        let isArrived = arrivalDate.map { $0 <= entry.date } ?? false

        let lineName = watchShortName(from: firstLeg?.serviceName)
        let depTime = WidgetDataProvider.formatTime(trip.startTime)

        if isArrived {
            return Text(Image(systemName: "checkmark.circle.fill")) + Text(" \(lineName) Angekommen")
        } else if isBeforeDeparture, let depDate = departureDate {
            let mins = max(0, Int(depDate.timeIntervalSince(entry.date) / 60))
            if mins == 0 {
                return Text(Image(systemName: "tram.fill")) + Text(" \(lineName) Jetzt · \(depTime)")
            } else {
                return Text(Image(systemName: "clock.fill")) + Text(" \(lineName) in \(mins)' · \(depTime)")
            }
        } else {
            let arrTime = WidgetDataProvider.formatTime(trip.endTime)
            return Text(Image(systemName: "location.fill")) + Text(" \(lineName) → \(trip.endStation) \(arrTime)")
        }
    }
}

// MARK: - Watch-specific Style Helpers

/// Eigene leichtgewichtige Helfer für den Widget-Kontext (kein Import von StyleHelper nötig,
/// da die Logik identisch ist, aber hier nochmal kompakt enthalten).

private func watchLineColor(for serviceType: String?, serviceName: String? = nil) -> Color {
    let type = (serviceType ?? "").uppercased()
    let name = (serviceName ?? "").trimmingCharacters(in: .whitespaces).uppercased()

    // S-Bahn
    if type.contains("S_BAHN") || type.contains("SBAHN") || type.contains("SUBURBAN") { return .green }
    if name.count >= 2, name.hasPrefix("S"), name.dropFirst().first?.isNumber == true { return .green }

    // Fernverkehr
    if type.contains("ICE") || type.contains("INTERCITY") || type.contains("FERNVERKEHR") { return Color(white: 0.35) }
    if name.hasPrefix("ICE") || name.hasPrefix("IC") || name.hasPrefix("EC") { return Color(white: 0.35) }

    // Regional
    if type.contains("REGIONAL") || type.contains("_RE") || type.contains("RB") || type.contains("MEX") { return .purple }
    if name.hasPrefix("RE") || name.hasPrefix("RB") || name.hasPrefix("MEX") { return .purple }

    // Straßenbahn
    if type.contains("STRASSENBAHN") || type.contains("TRAM") { return .red }

    // Bus
    if type.contains("BUS") { return .blue }

    return .gray
}

private func watchLineIcon(for serviceType: String?, serviceName: String? = nil) -> String {
    let type = (serviceType ?? "").uppercased()
    let name = (serviceName ?? "").trimmingCharacters(in: .whitespaces).uppercased()

    if type.contains("S_BAHN") || type.contains("SBAHN") || type.contains("SUBURBAN") { return "train.side.front.car" }
    if name.count >= 2, name.hasPrefix("S"), name.dropFirst().first?.isNumber == true { return "train.side.front.car" }

    if type.contains("ICE") || type.contains("INTERCITY") || type.contains("FERNVERKEHR") { return "train.side.front.car" }
    if name.hasPrefix("ICE") || name.hasPrefix("IC") || name.hasPrefix("EC") { return "train.side.front.car" }

    if type.contains("REGIONAL") { return "tram.fill" }
    if name.hasPrefix("RE") || name.hasPrefix("RB") || name.hasPrefix("MEX") { return "tram.fill" }

    if type.contains("STRASSENBAHN") || type.contains("TRAM") { return "lightrail.fill" }
    if type.contains("BUS") { return "bus.fill" }

    return "tram.fill"
}

private func watchShortName(from serviceName: String?) -> String {
    guard let name = serviceName else { return "?" }
    return name
        .replacingOccurrences(of: "RNV ", with: "")
        .replacingOccurrences(of: "rnv ", with: "")
        .replacingOccurrences(of: "Linie ", with: "")
}

// MARK: - Previews

#Preview("Rectangular – Fahrt", as: .accessoryRectangular) {
    WatchTripWidget()
} timeline: {
    WatchTripEntry(date: Date(), trip: WidgetPreviewData.sampleTrip, isPlaceholder: false)
}

#Preview("Rectangular – Leer", as: .accessoryRectangular) {
    WatchTripWidget()
} timeline: {
    WatchTripEntry(date: Date(), trip: nil, isPlaceholder: false)
}

#Preview("Circular – Fahrt", as: .accessoryCircular) {
    WatchTripWidget()
} timeline: {
    WatchTripEntry(date: Date(), trip: WidgetPreviewData.sampleTrip, isPlaceholder: false)
}

#Preview("Circular – Leer", as: .accessoryCircular) {
    WatchTripWidget()
} timeline: {
    WatchTripEntry(date: Date(), trip: nil, isPlaceholder: false)
}

#Preview("Inline – Fahrt", as: .accessoryInline) {
    WatchTripWidget()
} timeline: {
    WatchTripEntry(date: Date(), trip: WidgetPreviewData.sampleTrip, isPlaceholder: false)
}
