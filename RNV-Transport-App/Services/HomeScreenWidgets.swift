//
//  HomeScreenWidgets.swift
//  RNVLiveActivity
//
//  Homescreen-Widgets für ÖPNV Mannheim & Umgebung
//

import WidgetKit
import SwiftUI

// MARK: - Shared Widget Data Provider

struct WidgetDataProvider {
    static let appGroupID = "group.com.stefanfriedrich.rnvapp"

    static func loadActiveTrips() -> [String] {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return [] }
        return defaults.stringArray(forKey: "activeTrips") ?? []
    }

    static func loadSavedTrips() -> [WidgetTripData] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: "savedTripData") else { return [] }
        do {
            return try JSONDecoder().decode([WidgetTripData].self, from: data)
        } catch {
            return []
        }
    }

    static func loadNextTrip() -> WidgetTripData? {
        let now = Date()
        let trips = loadSavedTrips()
        let activeIds = Set(loadActiveTrips())
        return trips
            .filter { activeIds.contains($0.id) }
            .filter { trip in
                guard let endDate = parseISO8601(trip.endTime) else { return false }
                return endDate > now
            }
            .sorted { a, b in
                let dateA = parseISO8601(a.startTime) ?? .distantFuture
                let dateB = parseISO8601(b.startTime) ?? .distantFuture
                return dateA < dateB
            }
            .first
    }

    private static let isoFormatterWithFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterWithout: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    static func parseISO8601(_ string: String) -> Date? {
        if let date = isoFormatterWithFrac.date(from: string) { return date }
        return isoFormatterWithout.date(from: string)
    }

    static func formatTime(_ isoString: String) -> String {
        guard let date = parseISO8601(isoString) else { return "--:--" }
        return timeFormatter.string(from: date)
    }

    static func calculateDuration(start: String, end: String) -> String {
        guard let startDate = parseISO8601(start),
              let endDate = parseISO8601(end) else { return "?" }
        let minutes = Int(endDate.timeIntervalSince(startDate) / 60)
        return "\(minutes) min"
    }
}

// MARK: - Codable Trip Model for Widgets

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

    var isTimedLeg: Bool {
        legType == "TimedLeg"
    }
}

// MARK: - Widget Theme

struct WidgetTheme {
    static let primaryColor = Color(red: 0.0, green: 0.55, blue: 0.65)
    static let secondaryColor = Color(red: 0.30, green: 0.25, blue: 0.65)
    static let accentGradient = LinearGradient(
        colors: [primaryColor, secondaryColor],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Service Name Helpers

    private static func isSBahn(_ name: String) -> Bool {
        let n = name.uppercased().replacingOccurrences(of: " ", with: "")
        return n.hasPrefix("S") && n.dropFirst().first?.isNumber == true
    }

    private static func isRegionalLine(_ name: String) -> Bool {
        let n = name.uppercased().replacingOccurrences(of: " ", with: "")
        if n.hasPrefix("RE") || n.hasPrefix("RB") || n.hasPrefix("MEX") {
            let rest = n.hasPrefix("MEX") ? n.dropFirst(3) : n.dropFirst(2)
            return rest.first?.isNumber == true || rest.isEmpty
        }
        return false
    }

    private static func isLongDistanceLine(_ name: String) -> Bool {
        let n = name.uppercased().replacingOccurrences(of: " ", with: "")
        return n.hasPrefix("ICE") || n.hasPrefix("IC") || n.hasPrefix("EC") || n.hasPrefix("TGV") || n.hasPrefix("RJX") || n.hasPrefix("FLX")
    }

    static func lineColor(for serviceType: String?, serviceName: String? = nil) -> Color {
        switch serviceType?.uppercased() {
        case "STRASSENBAHN", "TRAM": return .red
        case "BUS": return .blue
        case "S_BAHN", "SBAHN": return .green
        case "REGIONAL", "REGIONALBAHN": return Color(red: 0.4, green: 0.1, blue: 0.6)
        case "FERNVERKEHR", "LONGDISTANCE", "INTERCITY": return Color(red: 0.55, green: 0.0, blue: 0.05)
        default: break
        }
        if let name = serviceName, !name.isEmpty {
            if isSBahn(name) { return .green }
            if isRegionalLine(name) { return Color(red: 0.4, green: 0.1, blue: 0.6) }
            if isLongDistanceLine(name) { return Color(red: 0.55, green: 0.0, blue: 0.05) }
        }
        return .gray
    }

    static func lineIcon(for serviceType: String?, serviceName: String? = nil) -> String {
        switch serviceType?.uppercased() {
        case "STRASSENBAHN", "TRAM": return "lightrail.fill"
        case "BUS": return "bus.fill"
        case "S_BAHN", "SBAHN": return "s.circle.fill"
        case "REGIONAL", "REGIONALBAHN": return "tram.fill"
        case "FERNVERKEHR", "LONGDISTANCE", "INTERCITY": return "train.side.front.car"
        default: break
        }
        if let name = serviceName, !name.isEmpty {
            if isSBahn(name) { return "s.circle.fill" }
            if isRegionalLine(name) { return "tram.fill" }
            if isLongDistanceLine(name) { return "train.side.front.car" }
        }
        return "questionmark"
    }

    static func shortLineName(from serviceName: String?) -> String {
        guard let name = serviceName else { return "?" }
        return name
            .replacingOccurrences(of: "RNV ", with: "")
            .replacingOccurrences(of: "rnv ", with: "")
            .replacingOccurrences(of: "Linie ", with: "")
    }
}

// MARK: - Reusable Components

struct WidgetLineBadge: View {
    let serviceType: String?
    let serviceName: String?
    let compact: Bool

    init(serviceType: String?, serviceName: String?, compact: Bool = false) {
        self.serviceType = serviceType
        self.serviceName = serviceName
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            Image(systemName: WidgetTheme.lineIcon(for: serviceType, serviceName: serviceName))
                .font(.system(size: compact ? 9 : 11, weight: .bold))
            Text(WidgetTheme.shortLineName(from: serviceName))
                .font(.system(size: compact ? 10 : 12, weight: .heavy, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 5)
        .background(
            RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                .fill(WidgetTheme.lineColor(for: serviceType, serviceName: serviceName))
        )
    }
}

struct WidgetCountdownChip: View {
    let minutes: Int
    let isActive: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isActive ? "location.fill" : "clock.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(isActive ? "Unterwegs" : "in \(minutes) Min")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(isActive ? Color.green : WidgetTheme.primaryColor)
        )
    }
}

struct WidgetRouteRow: View {
    let from: String
    let to: String

    var body: some View {
        HStack(spacing: 6) {
            VStack(spacing: 4) {
                Circle().fill(Color.green.opacity(0.8)).frame(width: 6, height: 6)
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
                Circle().fill(Color.red.opacity(0.8)).frame(width: 6, height: 6)
            }
            .frame(width: 8)
            .padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(from)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(to)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 36)
    }
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 1. Nächste Abfahrt Widget (Small + Medium)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct NextDepartureEntry: TimelineEntry {
    let date: Date
    let trip: WidgetTripData?
    let isPlaceholder: Bool
}

struct NextDepartureProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextDepartureEntry {
        NextDepartureEntry(date: Date(), trip: nil, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextDepartureEntry) -> Void) {
        let trip = WidgetDataProvider.loadNextTrip()
        completion(NextDepartureEntry(date: Date(), trip: trip, isPlaceholder: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextDepartureEntry>) -> Void) {
        let trip = WidgetDataProvider.loadNextTrip()
        let now = Date()
        var entries: [NextDepartureEntry] = []
        for i in 0..<15 {
            let entryDate = now.addingTimeInterval(Double(i) * 60)
            entries.append(NextDepartureEntry(date: entryDate, trip: trip, isPlaceholder: false))
        }
        let nextRefresh = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }
}

// MARK: Small View

struct NextDepartureWidgetSmallView: View {
    let entry: NextDepartureEntry

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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 50, height: 24)
                Spacer()
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 64, height: 22)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 32)
            Spacer()
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 14)
        }
        .padding(14)
    }

    private func tripView(_ trip: WidgetTripData) -> some View {
        let firstLeg = trip.legs.first(where: { $0.isTimedLeg })
        let departureDate = WidgetDataProvider.parseISO8601(trip.startTime)
        let isBeforeDeparture = departureDate.map { $0 > entry.date } ?? false

        return VStack(alignment: .leading, spacing: 0) {
            // Top: Badge + Time
            HStack(alignment: .top) {
                if let leg = firstLeg {
                    WidgetLineBadge(serviceType: leg.serviceType, serviceName: leg.serviceName)
                }
                Spacer()
                if isBeforeDeparture, let depDate = departureDate {
                    let mins = max(0, Int(depDate.timeIntervalSince(entry.date) / 60))
                    Text("\(mins)'")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(WidgetTheme.primaryColor)
                } else {
                    HStack(spacing: 3) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Live")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                }
            }

            Spacer().frame(height: 10)

            // Route
            WidgetRouteRow(from: trip.startStation, to: trip.endStation)

            Spacer()

            // Bottom: Times
            HStack(spacing: 0) {
                Text(WidgetDataProvider.formatTime(trip.startTime))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(" → ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Text(WidgetDataProvider.formatTime(trip.endTime))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text(WidgetDataProvider.calculateDuration(start: trip.startTime, end: trip.endTime))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tram.fill")
                .font(.system(size: 28))
                .foregroundStyle(WidgetTheme.primaryColor.opacity(0.3))
            Text("Keine Fahrten")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Starte eine\nLive-Verfolgung")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(14)
    }
}

// MARK: Medium View

struct NextDepartureWidgetMediumView: View {
    let entry: NextDepartureEntry

    var body: some View {
        if let trip = entry.trip {
            tripMediumView(trip)
        } else {
            emptyMediumView
        }
    }

    private func tripMediumView(_ trip: WidgetTripData) -> some View {
        let timedLegs = trip.legs.filter { $0.isTimedLeg }
        let departureDate = WidgetDataProvider.parseISO8601(trip.startTime)
        let isBeforeDeparture = departureDate.map { $0 > entry.date } ?? false

        return HStack(spacing: 14) {
            // Left: Route info
            VStack(alignment: .leading, spacing: 8) {
                // Line badges
                HStack(spacing: 5) {
                    ForEach(Array(timedLegs.prefix(3).enumerated()), id: \.offset) { _, leg in
                        WidgetLineBadge(serviceType: leg.serviceType, serviceName: leg.serviceName, compact: true)
                    }
                }

                // Route
                WidgetRouteRow(from: trip.startStation, to: trip.endStation)

                Spacer(minLength: 0)

                // Interchanges
                if trip.interchanges == 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                        Text("Direkt")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.green)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 9))
                        Text("\(trip.interchanges) Umstieg\(trip.interchanges == 1 ? "" : "e")")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                }
            }

            // Divider
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 1.5)
                .padding(.vertical, 4)

            // Right: Time + Status
            VStack(alignment: .trailing, spacing: 6) {
                // Departure time large
                VStack(alignment: .trailing, spacing: 1) {
                    Text(WidgetDataProvider.formatTime(trip.startTime))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    HStack(spacing: 3) {
                        Text("→ " + WidgetDataProvider.formatTime(trip.endTime))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(WidgetDataProvider.calculateDuration(start: trip.startTime, end: trip.endTime))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)

                // Status chip
                if isBeforeDeparture, let depDate = departureDate {
                    let mins = max(0, Int(depDate.timeIntervalSince(entry.date) / 60))
                    WidgetCountdownChip(minutes: mins, isActive: false)
                } else {
                    WidgetCountdownChip(minutes: 0, isActive: true)
                }
            }
            .frame(minWidth: 100)
        }
        .padding(14)
    }

    private var emptyMediumView: some View {
        HStack(spacing: 14) {
            Image(systemName: "tram.fill")
                .font(.system(size: 32))
                .foregroundStyle(WidgetTheme.primaryColor.opacity(0.3))

            VStack(alignment: .leading, spacing: 4) {
                Text("Keine aktiven Fahrten")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Suche eine Verbindung und starte die Live-Verfolgung")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
    }
}

struct NextDepartureWidget: Widget {
    let kind = "NextDepartureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextDepartureProvider()) { entry in
            if #available(iOS 17.0, *) {
                NextDepartureWidgetContainerView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                NextDepartureWidgetContainerView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Nächste Abfahrt")
        .description("Zeigt deine nächste geplante Fahrt.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextDepartureWidgetContainerView: View {
    @Environment(\.widgetFamily) var family
    let entry: NextDepartureEntry

    var body: some View {
        switch family {
        case .systemMedium:
            NextDepartureWidgetMediumView(entry: entry)
        default:
            NextDepartureWidgetSmallView(entry: entry)
        }
    }
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 2. Aktive Fahrten Widget (Medium + Large)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct ActiveTripsEntry: TimelineEntry {
    let date: Date
    let trips: [WidgetTripData]
    let activeCount: Int
}

struct ActiveTripsProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveTripsEntry {
        ActiveTripsEntry(date: Date(), trips: [], activeCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveTripsEntry) -> Void) {
        let activeIds = Set(WidgetDataProvider.loadActiveTrips())
        let allTrips = WidgetDataProvider.loadSavedTrips()
        let activeTrips = allTrips.filter { activeIds.contains($0.id) }
        completion(ActiveTripsEntry(date: Date(), trips: activeTrips, activeCount: activeIds.count))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveTripsEntry>) -> Void) {
        let activeIds = Set(WidgetDataProvider.loadActiveTrips())
        let allTrips = WidgetDataProvider.loadSavedTrips()
        let activeTrips = allTrips.filter { activeIds.contains($0.id) }
        let now = Date()
        var entries: [ActiveTripsEntry] = []
        for i in 0..<15 {
            let entryDate = now.addingTimeInterval(Double(i) * 60)
            entries.append(ActiveTripsEntry(date: entryDate, trips: activeTrips, activeCount: activeIds.count))
        }
        let nextRefresh = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }
}

// MARK: Active Trip Row

struct ActiveTripRow: View {
    let trip: WidgetTripData
    let currentDate: Date

    private var firstTimedLeg: WidgetTripLegData? {
        trip.legs.first(where: { $0.isTimedLeg })
    }

    private var departureDate: Date? {
        WidgetDataProvider.parseISO8601(trip.startTime)
    }

    private var arrivalDate: Date? {
        WidgetDataProvider.parseISO8601(trip.endTime)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Line badge (square)
            if let leg = firstTimedLeg {
                VStack(spacing: 2) {
                    Image(systemName: WidgetTheme.lineIcon(for: leg.serviceType, serviceName: leg.serviceName))
                        .font(.system(size: 12, weight: .bold))
                    Text(WidgetTheme.shortLineName(from: leg.serviceName))
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WidgetTheme.lineColor(for: leg.serviceType, serviceName: leg.serviceName))
                )
            }

            // Route + times
            VStack(alignment: .leading, spacing: 3) {
                Text("\(trip.startStation) → \(trip.endStation)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(WidgetDataProvider.formatTime(trip.startTime))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(WidgetDataProvider.formatTime(trip.endTime))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status
            statusView
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if let depDate = departureDate, depDate > currentDate {
            let minutes = max(0, Int(depDate.timeIntervalSince(currentDate) / 60))
            Text("\(minutes)'")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(WidgetTheme.primaryColor)
        } else if let arrDate = arrivalDate, arrDate > currentDate {
            HStack(spacing: 3) {
                Circle().fill(Color.green).frame(width: 5, height: 5)
                Text("Fährt")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.green)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
        }
    }
}

// MARK: Medium View

struct ActiveTripsWidgetMediumView: View {
    let entry: ActiveTripsEntry

    var body: some View {
        if entry.trips.isEmpty {
            emptyView
        } else {
            tripsView
        }
    }

    private var tripsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetTheme.primaryColor)
                    Text("Aktive Fahrten")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
                Spacer()
                Text("\(entry.activeCount)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(WidgetTheme.primaryColor))
            }

            // Trip rows
            ForEach(Array(entry.trips.prefix(2).enumerated()), id: \.offset) { _, trip in
                ActiveTripRow(trip: trip, currentDate: entry.date)
            }

            if entry.trips.count > 2 {
                Text("+ \(entry.trips.count - 2) weitere")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
    }

    private var emptyView: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 26))
                .foregroundStyle(WidgetTheme.primaryColor.opacity(0.3))

            VStack(alignment: .leading, spacing: 3) {
                Text("Keine aktiven Fahrten")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Aktiviere die Live-Verfolgung für eine Verbindung")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(14)
    }
}

// MARK: Large View

struct ActiveTripsWidgetLargeView: View {
    let entry: ActiveTripsEntry

    var body: some View {
        if entry.trips.isEmpty {
            emptyLargeView
        } else {
            tripsLargeView
        }
    }

    private var tripsLargeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WidgetTheme.accentGradient)
                        .frame(width: 32, height: 32)
                    Image(systemName: "tram.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("ÖPNV Mannheim")
                        .font(.system(size: 13, weight: .bold))
                    Text("Aktive Fahrten")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(entry.activeCount) aktiv")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(WidgetTheme.primaryColor))
            }
            .padding(.bottom, 10)

            Divider()

            // Trips
            ForEach(Array(entry.trips.prefix(4).enumerated()), id: \.offset) { index, trip in
                ActiveTripRow(trip: trip, currentDate: entry.date)
                    .padding(.vertical, 8)

                if index < min(entry.trips.count - 1, 3) {
                    Divider().padding(.leading, 48)
                }
            }

            if entry.trips.count > 4 {
                HStack {
                    Spacer()
                    Text("+ \(entry.trips.count - 4) weitere Fahrten")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var emptyLargeView: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .fill(WidgetTheme.primaryColor.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "tram.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(WidgetTheme.primaryColor.opacity(0.35))
            }

            Text("Keine aktiven Fahrten")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)

            Text("Öffne die App, suche eine Verbindung\nund starte die Live-Verfolgung")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(14)
    }
}

struct ActiveTripsWidget: Widget {
    let kind = "ActiveTripsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveTripsProvider()) { entry in
            if #available(iOS 17.0, *) {
                ActiveTripsWidgetContainerView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ActiveTripsWidgetContainerView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Aktive Fahrten")
        .description("Übersicht aller aktuell verfolgten Fahrten.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ActiveTripsWidgetContainerView: View {
    @Environment(\.widgetFamily) var family
    let entry: ActiveTripsEntry

    var body: some View {
        switch family {
        case .systemLarge:
            ActiveTripsWidgetLargeView(entry: entry)
        default:
            ActiveTripsWidgetMediumView(entry: entry)
        }
    }
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 3. Schnellsuche Widget (Small)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct QuickSearchEntry: TimelineEntry {
    let date: Date
    let activeCount: Int
}

struct QuickSearchProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickSearchEntry {
        QuickSearchEntry(date: Date(), activeCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickSearchEntry) -> Void) {
        let count = WidgetDataProvider.loadActiveTrips().count
        completion(QuickSearchEntry(date: Date(), activeCount: count))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickSearchEntry>) -> Void) {
        let count = WidgetDataProvider.loadActiveTrips().count
        let entry = QuickSearchEntry(date: Date(), activeCount: count)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct QuickSearchWidgetView: View {
    let entry: QuickSearchEntry

    var body: some View {
        VStack(spacing: 0) {
            // Top gradient area
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.06, green: 0.10, blue: 0.20),
                                Color(red: 0.0, green: 0.35, blue: 0.42)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(2)

                VStack(spacing: 5) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))

                    Text("ÖPNV")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Mannheim")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)

            Spacer().frame(height: 8)

            // Search prompt
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                Text("Verbindung suchen")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(WidgetTheme.primaryColor)

            Spacer().frame(height: 6)

            // Status
            if entry.activeCount > 0 {
                HStack(spacing: 3) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("\(entry.activeCount) aktiv")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.green)
                }
            } else {
                Text(currentTimeString())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
    }

    private func currentTimeString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.locale = Locale(identifier: "de_DE")
        return fmt.string(from: entry.date)
    }
}

struct QuickSearchWidget: Widget {
    let kind = "QuickSearchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickSearchProvider()) { entry in
            if #available(iOS 17.0, *) {
                QuickSearchWidgetView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                QuickSearchWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Schnellsuche")
        .description("Öffne die App direkt zur Verbindungssuche.")
        .supportedFamilies([.systemSmall])
    }
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Widget Previews
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum WidgetPreviewData {
    static let sampleTrip = WidgetTripData(
        id: UUID().uuidString,
        startTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(600)),
        endTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(2400)),
        interchanges: 0,
        startStation: "Mannheim Hbf",
        endStation: "Heidelberg Bismarckplatz",
        legs: [
            WidgetTripLegData(
                legType: "TimedLeg",
                boardStopName: "Mannheim Hbf",
                alightStopName: "Heidelberg Bismarckplatz",
                departureTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(600)),
                arrivalTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(2400)),
                serviceName: "Linie 5",
                serviceType: "STRASSENBAHN",
                destinationLabel: "Heidelberg Hbf"
            )
        ]
    )

    static let sampleTrips = [
        sampleTrip,
        WidgetTripData(
            id: UUID().uuidString,
            startTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300)),
            endTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(1500)),
            interchanges: 1,
            startStation: "Paradeplatz",
            endStation: "Neuostheim",
            legs: [
                WidgetTripLegData(
                    legType: "TimedLeg",
                    boardStopName: "Paradeplatz",
                    alightStopName: "Neuostheim",
                    departureTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300)),
                    arrivalTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(1500)),
                    serviceName: "Linie 1",
                    serviceType: "STRASSENBAHN",
                    destinationLabel: "Schönau"
                )
            ]
        )
    ]
}