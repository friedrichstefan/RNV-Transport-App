//
//  DepartureBoardView.swift
//  RNV-Transport-App
//

import SwiftUI
import CoreLocation

struct DepartureBoardView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var locationManager: LocationManager

    @StateObject private var service = GraphQLService()
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @ObservedObject private var network = NetworkMonitor.shared

    @State private var selectedStation: Station?
    @State private var departures: [Departure] = []
    @State private var isLoadingDepartures = false
    @State private var departureError: String?
    @State private var showStationPicker = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var lastRefresh: Date?
    @State private var loadEpoch: Int = 0
    @State private var selectedDeparture: Departure?
    @State private var departureDate: Date = Date()
    @State private var departureDisplayLimit: Int = 10

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private let formatter = DateFormattingHelper.shared

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.canvasAdaptive(colorScheme).ignoresSafeArea()

                // Gradient pinned to top — bleeds behind navigation bar up to Dynamic Island
                VStack {
                    RadialGradient(
                        colors: [AppTheme.gradientLavender.opacity(0.5), .clear],
                        center: .init(x: 0.5, y: 0.25),
                        startRadius: 0,
                        endRadius: 220
                    )
                    .frame(height: 220)
                    .ignoresSafeArea(edges: .top)
                    Spacer()
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    heroHeader
                        .background(AppTheme.canvasAdaptive(colorScheme))

                    if !network.isConnected {
                        offlineBanner
                    }

                    ScrollView {
                        VStack(spacing: 0) {
                            if isLoadingDepartures && departures.isEmpty && departureError == nil {
                                loadingView
                            } else if let error = departureError {
                                errorView(error)
                            } else if departures.isEmpty && selectedStation != nil {
                                noDeparturesView
                            } else if selectedStation == nil {
                                promptView
                            } else {
                                departureList
                            }
                        }
                    }
                    .refreshable { await loadDepartures() }
                }
            }
            .navigationTitle("Abfahrten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoadingDepartures {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(AppTheme.muted)
                    } else {
                        Button(action: refreshDepartures) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.muted)
                        }
                        .accessibilityLabel("Aktualisieren")
                    }
                }
            }
            .sheet(isPresented: $showStationPicker) {
                StationPickerView(
                    authService: authService,
                    graphQLService: service,
                    locationManager: locationManager,
                    selectedStation: $selectedStation,
                    selectedDate: $departureDate
                )
            }
            .sheet(item: $selectedDeparture) { dep in
                DepartureTripDetailView(
                    departure: dep,
                    graphQLService: service,
                    authService: authService
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: selectedStation) {
                departureDisplayLimit = 10
                Task { await loadDepartures() }
            }
            .onChange(of: departureDate) {
                Task { await loadDepartures() }
            }
            .onAppear {
                loadNearbyStationIfNeeded()
                startAutoRefresh()
            }
            .onDisappear {
                refreshTask?.cancel()
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                // Section label
                Text("ABFAHRTEN")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.muted)
                    .tracking(1.4)

                // Station name — display serif
                if let station = selectedStation {
                    Text(station.longName)
                        .font(AppTheme.displayFont(size: 28))
                        .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 32)
                } else {
                    Text("Keine Haltestelle")
                        .font(AppTheme.displayFont(size: 28))
                        .foregroundColor(AppTheme.muted)
                }

                // Meta row
                HStack(spacing: 12) {
                    if let last = lastRefresh {
                        Text("Aktuell um \(formatter.formatTimeFromDate(last)) Uhr")
                            .font(.caption)
                            .foregroundColor(AppTheme.mutedAdaptive(colorScheme, contrast: colorSchemeContrast))
                    }
                    if !Calendar.current.isDateInToday(departureDate) {
                        Text(formatter.formatDateShort(departureDate))
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppTheme.primaryColor)
                    }
                    Button(action: { showStationPicker = true }) {
                        HStack(spacing: 3) {
                            Text(lastRefresh == nil ? "Haltestelle wählen" : "Ändern")
                                .font(.caption.weight(.medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(AppTheme.primaryColor)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.top, 8)
            .padding(.bottom, 20)

            // Hairline separator
            AppTheme.hairlineAdaptive(colorScheme)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(selectedStation.map { "Abfahrten für \($0.longName)" } ?? "Haltestelle auswählen")
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.muted)
            Text("Kein Internet – Daten könnten veraltet sein")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.muted)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(AppTheme.surfaceStrongAdaptive(colorScheme))
        .overlay(
            AppTheme.hairlineAdaptive(colorScheme).frame(height: 1),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kein Internet – angezeigte Daten könnten veraltet sein")
    }

    // MARK: - Departure List

    private var departureList: some View {
        let visible = Array(departures.prefix(departureDisplayLimit))
        let hasMore = departures.count > departureDisplayLimit

        return VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, dep in
                Button {
                    HapticHelper.selection()
                    selectedDeparture = dep
                } label: {
                    DepartureRowView(departure: dep)
                }
                .buttonStyle(.plain)
                if index < visible.count - 1 {
                    AppTheme.hairlineAdaptive(colorScheme)
                        .frame(height: 1)
                        .padding(.leading, 20)
                }
            }

            if hasMore {
                AppTheme.hairlineAdaptive(colorScheme)
                    .frame(height: 1)

                Button {
                    HapticHelper.impact(.light)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        departureDisplayLimit += 10
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(departures.count - departureDisplayLimit) weitere Abfahrten")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.mutedAdaptive(colorScheme, contrast: colorSchemeContrast))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(departures.count - departureDisplayLimit) weitere Abfahrten anzeigen")
            }
        }
        .padding(.bottom, 48)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 64)
            ProgressView()
                .tint(AppTheme.muted)
            Text("Lade Abfahrten …")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.muted)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Abfahrten werden geladen")
    }

    // MARK: - Prompt

    private var promptView: some View {
        VStack(spacing: 32) {
            Spacer().frame(height: 48)

            ZStack {
                RadialGradient(
                    colors: [AppTheme.gradientMint.opacity(0.5), .clear],
                    center: .center, startRadius: 0, endRadius: 100
                )
                .frame(width: 220, height: 220)

                VStack(spacing: 12) {
                    Text("Wähle eine\nHaltestelle")
                        .font(AppTheme.displayFont(size: 30))
                        .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                        .multilineTextAlignment(.center)

                    Text("Um aktuelle Abfahrten\nin deiner Nähe zu sehen.")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.muted)
                        .multilineTextAlignment(.center)
                }
            }

            Button(action: { showStationPicker = true }) {
                Text("Haltestelle auswählen")
                    .font(AppTheme.buttonFont)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.primary)
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - No Departures

    private var noDeparturesView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 64)

            ZStack {
                RadialGradient(
                    colors: [AppTheme.gradientPeach.opacity(0.45), .clear],
                    center: .center, startRadius: 0, endRadius: 90
                )
                .frame(width: 180, height: 180)

                Text("Keine\nAbfahrten")
                    .font(AppTheme.displayFont(size: 26))
                    .foregroundColor(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }

            Text("Für diese Haltestelle sind aktuell\nkeine Abfahrten verfügbar.")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.muted)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 64)

            ZStack {
                RadialGradient(
                    colors: [AppTheme.gradientRose.opacity(0.4), .clear],
                    center: .center, startRadius: 0, endRadius: 90
                )
                .frame(width: 180, height: 180)

                VStack(spacing: 8) {
                    Text("Nicht\nverfügbar")
                        .font(AppTheme.displayFont(size: 26))
                        .foregroundColor(AppTheme.muted)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.mutedSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }

            Button(action: refreshDepartures) {
                Text("Erneut versuchen")
                    .font(AppTheme.buttonFont)
                    .foregroundColor(AppTheme.primaryColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .overlay(Capsule().stroke(AppTheme.hairlineStrong, lineWidth: 1))
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Logic

    private func loadNearbyStationIfNeeded() {
        guard selectedStation == nil, let location = locationManager.location else { return }
        guard let token = authService.accessToken else { return }
        Task {
            await service.searchStations(lat: location.latitude, lon: location.longitude, accessToken: token)
            if let first = service.stations.first {
                selectedStation = first
            }
        }
    }

    private func loadDepartures() async {
        guard let station = selectedStation else { return }
        guard let token = authService.accessToken else { return }

        loadEpoch += 1
        let myEpoch = loadEpoch

        isLoadingDepartures = true
        departureError = nil
        let time = ISO8601DateFormatter().string(from: departureDate)
        let result = await service.getDepartures(station: station, accessToken: token, time: time)

        guard loadEpoch == myEpoch else { return }
        departures = result.departures.map { dep in
            guard dep.boardStopName == nil else { return dep }
            var d = dep
            d.boardStopName = station.longName
            return d
        }
        departureError = departures.isEmpty ? result.error : nil
        lastRefresh = Date()
        isLoadingDepartures = false
    }

    private func refreshDepartures() {
        Task { await loadDepartures() }
    }

    private func startAutoRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                guard !isLoadingDepartures else { continue }
                await loadDepartures()
            }
        }
    }
}

// MARK: - Departure Row

struct DepartureRowView: View {
    let departure: Departure
    private let formatter = DateFormattingHelper.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 16) {
            lineBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(departure.direction)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                    .lineLimit(1)
                Text(departure.serviceTypeDisplay)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppTheme.mutedAdaptive(colorScheme, contrast: colorSchemeContrast))
                    .tracking(0.2)
            }

            Spacer()

            occupancyBadge(departure.occupancy ?? .low)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatter.formatTime(departure.scheduledDeparture))
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundColor(AppTheme.inkAdaptive(colorScheme))

                if let delay = departure.delayMinutes, delay > 0 {
                    Text("+\(delay) min")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundColor(AppTheme.semanticError)
                } else if departure.delayMinutes == 0 {
                    Text("pünktlich")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppTheme.semanticSuccess)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(departure.lineName) Richtung \(departure.direction), \(formatter.formatTime(departure.scheduledDeparture))\(departure.delayMinutes.map { $0 > 0 ? ", +\($0) Minuten" : ", pünktlich" } ?? "")\(departure.occupancy.map { $0 != .unknown ? ", Auslastung \($0.displayText)" : "" } ?? "")")
        .accessibilityHint("Tippen für Details")
    }

    private func occupancyBadge(_ level: OccupancyLevel) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "person.fill")
                    .font(.system(size: 9, weight: .medium))
                    .opacity(i < level.filledCount ? 1.0 : 0.18)
            }
        }
        .foregroundColor(level.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Capsule().fill(level.color.opacity(0.1)))
    }

    private var lineBadge: some View {
        Text(TransportIconHelper.getShortLineName(from: departure.lineName))
            .font(Font.system(.caption, design: .monospaced).weight(.bold))
            .foregroundColor(.white)
            .frame(minWidth: 38, minHeight: 28)
            .padding(.horizontal, 6)
            .background(Capsule().fill(departure.lineColor))
    }
}

// MARK: - Departure Stop Model

struct DepartureStop: Identifiable {
    let id = UUID()
    let name: String
    let scheduledTime: String?
    let estimatedTime: String?

    var delayMinutes: Int? {
        let fmt = DateFormattingHelper.shared
        guard let scheduled = scheduledTime.flatMap({ fmt.parseISO8601($0) }),
              let estimated = estimatedTime.flatMap({ fmt.parseISO8601($0) }) else { return nil }
        return max(0, Int(estimated.timeIntervalSince(scheduled) / 60))
    }

    var formattedTime: String? {
        guard let t = scheduledTime else { return nil }
        return DateFormattingHelper.shared.formatTime(t)
    }
}

// MARK: - Departure Model

struct Departure: Identifiable {
    let id = UUID()
    let scheduledDeparture: String
    let estimatedDeparture: String?
    let lineName: String
    let direction: String
    let serviceType: String?
    var boardStopName: String? = nil
    var intermediateStops: [DepartureStop] = []
    var finalStop: DepartureStop? = nil
    var originGlobalID: String = ""
    var occupancy: OccupancyLevel? = nil

    var delayMinutes: Int? {
        let fmt = DateFormattingHelper.shared
        guard let scheduled = fmt.parseISO8601(scheduledDeparture),
              let estimated = estimatedDeparture.flatMap({ fmt.parseISO8601($0) }) else { return nil }
        return max(0, Int(estimated.timeIntervalSince(scheduled) / 60))
    }

    var serviceTypeDisplay: String {
        switch serviceType?.uppercased() {
        case "TRAM": return "Straßenbahn"
        case "BUS": return "Bus"
        case "SUBURBAN": return "S-Bahn"
        case "RAIL": return "Zug"
        default: return serviceType?.capitalized ?? "ÖPNV"
        }
    }

    var lineColor: Color {
        TransportIconHelper.getLineColor(for: serviceType, serviceName: lineName)
    }

    var minutesUntilDeparture: Int? {
        let fmt = DateFormattingHelper.shared
        guard let scheduled = fmt.parseISO8601(scheduledDeparture) else { return nil }
        let effective = estimatedDeparture.flatMap { fmt.parseISO8601($0) } ?? scheduled
        let diff = effective.timeIntervalSinceNow / 60
        return diff > -1 ? Int(diff) : nil
    }
}

// MARK: - Trip Detail Sheet

struct DepartureTripDetailView: View {
    let departure: Departure
    let graphQLService: GraphQLService
    let authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private let formatter = DateFormattingHelper.shared

    @State private var fullIntermediates: [DepartureStop]?
    @State private var fullFinalStop: DepartureStop?
    @State private var isLoadingFullRoute = false

    @ScaledMetric(relativeTo: .title) private var departureTimeSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title2) private var countdownSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title3) private var countdownUnitSize: CGFloat = 14

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.canvasAdaptive(colorScheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        headerSection
                        Divider().padding(.horizontal, 20)
                        statusSection
                        Divider().padding(.horizontal, 20)
                        if hasStopData {
                            stopTimelineSection
                        }
                        Spacer(minLength: 48)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.inkAdaptive(colorScheme))
                }
            }
            .task {
                await loadFullRoute()
            }
        }
    }

    private func loadFullRoute() async {
        guard !departure.originGlobalID.isEmpty,
              let token = authService.accessToken else { return }
        isLoadingFullRoute = true
        let result = await graphQLService.fetchFullDepartureRoute(
            originID: departure.originGlobalID,
            direction: departure.direction,
            lineName: departure.lineName,
            scheduledDeparture: departure.scheduledDeparture,
            accessToken: token
        )
        if !result.intermediates.isEmpty || result.finalStop != nil {
            fullIntermediates = result.intermediates
            fullFinalStop = result.finalStop
        }
        isLoadingFullRoute = false
    }

    private var hasStopData: Bool {
        departure.boardStopName != nil || !departure.intermediateStops.isEmpty || departure.finalStop != nil
    }

    private var effectiveIntermediates: [DepartureStop] {
        fullIntermediates ?? departure.intermediateStops
    }

    private var effectiveFinalStop: DepartureStop? {
        fullFinalStop ?? departure.finalStop
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                lineBadge
                VStack(alignment: .leading, spacing: 3) {
                    Text("nach \(departure.direction)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.inkAdaptive(colorScheme))
                        .lineLimit(2)
                    Text(departure.serviceTypeDisplay.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                        .tracking(0.5)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(departure.serviceTypeDisplay) \(departure.lineName) Richtung \(departure.direction)")
    }

    private var lineBadge: some View {
        Text(TransportIconHelper.getShortLineName(from: departure.lineName))
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .frame(minWidth: 52, minHeight: 36)
            .padding(.horizontal, 10)
            .background(Capsule().fill(departure.lineColor))
    }

    // MARK: Status

    private var statusSection: some View {
        HStack(spacing: 0) {
            departureTimeBlock
            Divider().frame(height: 56)
            countdownBlock
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            var label = "Abfahrt um \(formatter.formatTime(departure.scheduledDeparture))"
            if let delay = departure.delayMinutes {
                label += delay > 0 ? ", \(delay) Minuten Verspätung" : ", pünktlich"
            }
            if let mins = departure.minutesUntilDeparture {
                label += mins == 0 ? ", Abfahrt jetzt" : ", Abfahrt in \(mins) Minuten"
            }
            return label
        }())
    }

    private var departureTimeBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Abfahrt")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.mutedAdaptive(colorScheme, contrast: colorSchemeContrast))
                .tracking(0.3)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatter.formatTime(departure.scheduledDeparture))
                    .font(.system(size: departureTimeSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.inkAdaptive(colorScheme))
                delayBadge
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var delayBadge: some View {
        if let delay = departure.delayMinutes {
            if delay > 0 {
                Text("+\(delay) min")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.semanticError))
            } else {
                Text("pünktlich")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.semanticSuccess)
            }
        }
    }

    private var countdownBlock: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Abfahrt in")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.mutedAdaptive(colorScheme, contrast: colorSchemeContrast))
                .tracking(0.3)
            if let mins = departure.minutesUntilDeparture {
                if mins == 0 {
                    Text("jetzt")
                        .font(.system(size: countdownSize * 0.78, weight: .bold))
                        .foregroundStyle(departure.lineColor)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(mins)")
                            .font(.system(size: countdownSize, weight: .semibold).monospacedDigit())
                            .foregroundStyle(AppTheme.inkAdaptive(colorScheme))
                        Text("min")
                            .font(.system(size: countdownUnitSize, weight: .medium))
                            .foregroundStyle(AppTheme.mutedAdaptive(colorScheme, contrast: colorSchemeContrast))
                    }
                }
            } else {
                Text("–")
                    .font(.system(size: countdownSize * 0.78, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedAdaptive(colorScheme, contrast: colorSchemeContrast))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: Stop Timeline

    private var stopTimelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Streckenverlauf")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
                    .tracking(0.5)
                    .accessibilityAddTraits(.isHeader)
                if isLoadingFullRoute {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            let allStops = buildStopList()
            ForEach(Array(allStops.enumerated()), id: \.offset) { index, stop in
                StopTimelineRow(
                    name: stop.name,
                    time: stop.time,
                    delay: stop.delay,
                    isFirst: index == 0,
                    isLast: index == allStops.count - 1,
                    lineColor: departure.lineColor,
                    isFinal: stop.isFinal
                )
            }

            if let finalStopName = effectiveFinalStop?.name,
               finalStopName != departure.direction {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.mutedSoft)
                    Text("Weiter bis \(departure.direction)")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.leading, 56)
                .padding(.top, 6)
                .padding(.bottom, 4)
            }
        }
    }

    private struct StopItem {
        let name: String
        let time: String?
        let delay: Int?
        let isFinal: Bool
    }

    private func buildStopList() -> [StopItem] {
        var stops: [StopItem] = []
        if let board = departure.boardStopName {
            stops.append(StopItem(
                name: board,
                time: formatter.formatTime(departure.scheduledDeparture),
                delay: departure.delayMinutes,
                isFinal: false
            ))
        }
        for s in effectiveIntermediates {
            stops.append(StopItem(
                name: s.name,
                time: s.formattedTime,
                delay: s.delayMinutes,
                isFinal: false
            ))
        }
        if let final_ = effectiveFinalStop {
            stops.append(StopItem(
                name: final_.name,
                time: final_.formattedTime,
                delay: final_.delayMinutes,
                isFinal: true
            ))
        }
        return stops
    }
}

// MARK: - Stop Timeline Row

private struct StopTimelineRow: View {
    let name: String
    let time: String?
    let delay: Int?
    let isFirst: Bool
    let isLast: Bool
    let lineColor: Color
    let isFinal: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Timeline column (fixed 56pt)
            ZStack {
                // Vertical line above dot
                if !isFirst {
                    Rectangle()
                        .fill(lineColor.opacity(0.35))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.bottom, 14)
                }
                // Vertical line below dot
                if !isLast {
                    Rectangle()
                        .fill(lineColor.opacity(0.35))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.top, 14)
                }
                // Dot
                Circle()
                    .fill(isFinal || isFirst ? lineColor : AppTheme.hairlineStrong)
                    .frame(width: isFinal || isFirst ? 12 : 8, height: isFinal || isFirst ? 12 : 8)
                    .overlay(
                        Circle().strokeBorder(lineColor, lineWidth: isFinal || isFirst ? 0 : 1.5)
                    )
            }
            .frame(width: 56)
            .accessibilityHidden(true)

            // Stop name + delay
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(isFinal || isFirst ? .subheadline.weight(.medium) : .subheadline)
                    .foregroundStyle(isFinal || isFirst ? Color.primary : Color.secondary)
                    .lineLimit(1)
                if let d = delay, d > 0 {
                    Text("+\(d) min")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.semanticError)
                }
            }
            .padding(.leading, 4)

            Spacer()

            // Time
            if let t = time {
                Text(t)
                    .font(isFinal || isFirst
                          ? .subheadline.weight(.semibold).monospacedDigit()
                          : .footnote.monospacedDigit())
                    .foregroundStyle(isFinal || isFirst ? Color.primary : Color.secondary)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            var parts: [String] = [name]
            if let t = time { parts.append("um \(t)") }
            if let d = delay, d > 0 { parts.append("+\(d) Minuten Verspätung") }
            return parts.joined(separator: ", ")
        }())
    }
}

#Preview {
    DepartureBoardView(
        authService: AuthService(),
        locationManager: LocationManager()
    )
    .environmentObject(LiveActivityManager())
}
