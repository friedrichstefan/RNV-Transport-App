//
//  ConnectionsView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 14.01.26.
//

import SwiftUI
import CoreLocation

struct ConnectionsView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var graphQLService: GraphQLService
    @ObservedObject var locationManager: LocationManager

    @EnvironmentObject var liveActivityManager: LiveActivityManager

    @AppStorage("showDelaysOnly") private var showDelaysOnly = false
    @AppStorage("maxConnections") private var maxConnections = 5
    @AppStorage("enableTram") private var enableTram = true
    @AppStorage("enableBus") private var enableBus = true
    @AppStorage("enableSBahn") private var enableSBahn = true

    @State private var selectedStartStation: Station?
    @State private var selectedEndStation: Station?
    @State private var showingStationPicker = false
    @State private var isPickingStartStation = true
    @State private var selectedTrip: DetailedTrip?
    @State private var selectedDateTime: Date = Date()
    @State private var tripTimeMode: TripTimeMode = .now
    @State private var currentSearchTime: Date = Date()
    @State private var hasSearchedOnce: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var headerAppeared = false
    @State private var sameStationValidationError = false

    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let formatter = DateFormattingHelper.shared

    private let maxHeaderHeight: CGFloat = 248
    private let minHeaderHeight: CGFloat = 62

    private var collapseProgress: CGFloat {
        min(1, max(0, scrollOffset / (maxHeaderHeight - minHeaderHeight)))
    }

    private var currentHeaderHeight: CGFloat {
        max(minHeaderHeight, maxHeaderHeight - scrollOffset)
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: -geo.frame(in: .named("scroll")).origin.y
                            )
                        }
                        .frame(height: 0)

                        Color.clear.frame(height: maxHeaderHeight + 8)

                        VStack(spacing: 14) {
                            if authService.isAuthenticating {
                                loadingView
                            } else if authService.isAuthenticated {
                                mainContent
                            } else {
                                manualLoginView
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = max(0, value)
                }

                collapsingHeader
                    .zIndex(1)

                if !network.isConnected {
                    VStack {
                        Spacer().frame(height: currentHeaderHeight)
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Kein Internet")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.orange)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Kein Internet – Verbindung nicht möglich")
                        Spacer()
                    }
                    .zIndex(2)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: network.isConnected)
                }
            }
            .background(
                AppTheme.canvasAdaptive(colorScheme)
                    .ignoresSafeArea()
            )
            .navigationBarHidden(true)
            .sheet(isPresented: $showingStationPicker) {
                StationPickerView(
                    authService: authService,
                    graphQLService: graphQLService,
                    locationManager: locationManager,
                    selectedStation: isPickingStartStation ? $selectedStartStation : $selectedEndStation,
                    selectedDate: $selectedDateTime
                )
            }
            .onChange(of: selectedStartStation) { sameStationValidationError = false }
            .onChange(of: selectedEndStation) { sameStationValidationError = false }
            .sheet(item: $selectedTrip) { trip in
                TripDetailView(trip: trip, authService: authService, liveActivityManager: liveActivityManager)
            }
            .refreshable {
                await searchConnections()
            }
        }
    }

    // MARK: - Collapsing Header

    private var collapsingHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                headerBackground

                if collapseProgress < 1 {
                    expandedHeaderContent
                        .offset(y: headerAppeared ? 0 : 12)
                        .opacity(headerAppeared ? Double(max(0, 1 - collapseProgress * 2)) : 0)
                        .padding(.bottom, 14)
                }

                if collapseProgress > 0.45 {
                    collapsedHeaderContent
                        .opacity(Double(min(1, (collapseProgress - 0.45) / 0.3)))
                        .padding(.bottom, 10)
                }
            }
            .frame(height: currentHeaderHeight)
            .clipShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 22 * (1 - collapseProgress),
                    bottomTrailingRadius: 22 * (1 - collapseProgress)
                )
            )
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        }
        .background {
            headerBackground
                .ignoresSafeArea(edges: .top)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.06)) {
                headerAppeared = true
            }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.55
                }
            }
        }
    }

    // MARK: - Header Background

    private var headerBackground: some View {
        ZStack {
            AppTheme.canvasAdaptive(colorScheme)
            RadialGradient(
                colors: [AppTheme.gradientMint.opacity(0.55), .clear],
                center: .topLeading, startRadius: 0, endRadius: 200
            )
            RadialGradient(
                colors: [AppTheme.gradientPeach.opacity(0.40), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 160
            )
            RadialGradient(
                colors: [AppTheme.gradientLavender.opacity(0.25), .clear],
                center: .init(x: 0.5, y: 1.2), startRadius: 0, endRadius: 140
            )
        }
    }

    // MARK: - Expanded Header Content

    private var expandedHeaderContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Greeting + time
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.greetingText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.mutedAdaptive(colorScheme, contrast: colorSchemeContrast))
                        .tracking(1.4)
                        .textCase(.uppercase)
                    Text("Verbindungen")
                        .font(AppTheme.displayFont(size: 24))
                        .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                }

                Spacer()

                TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                    Text(Self.headerTimeFormatter.string(from: timeline.date))
                        .font(AppTheme.monoFont(size: 18))
                        .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                        .contentTransition(.numericText())
                        .accessibilityLabel("Aktuelle Uhrzeit: \(Self.headerTimeFormatter.string(from: timeline.date))")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(AppTheme.surfaceStrongAdaptive(colorScheme))
                        .overlay(Capsule().stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
                )
            }

            // Station inputs
            VStack(spacing: 0) {
                headerStationRow(
                    icon: "circle.fill",
                    iconColor: Color(red: 0.2, green: 0.85, blue: 0.45),
                    placeholder: "Startpunkt wählen",
                    station: selectedStartStation
                ) {
                    isPickingStartStation = true
                    showingStationPicker = true
                }

                HStack(spacing: 0) {
                    AppTheme.hairlineAdaptive(colorScheme).frame(height: 1)
                    Button {
                        HapticHelper.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            swap(&selectedStartStation, &selectedEndStation)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.muted)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppTheme.surfaceStrongAdaptive(colorScheme)))
                    }
                    .disabled(selectedStartStation == nil && selectedEndStation == nil)
                    .accessibilityLabel("Start und Ziel tauschen")
                    AppTheme.hairlineAdaptive(colorScheme).frame(height: 1)
                }
                .padding(.horizontal, 14)

                headerStationRow(
                    icon: "mappin.circle.fill",
                    iconColor: Color(red: 1.0, green: 0.35, blue: 0.35),
                    placeholder: "Ziel wählen",
                    station: selectedEndStation
                ) {
                    isPickingStartStation = false
                    showingStationPicker = true
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func headerStationRow(icon: String, iconColor: Color, placeholder: String, station: Station?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 10))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(AppTheme.surfaceStrongAdaptive(colorScheme)))

                Text(station?.longName ?? placeholder)
                    .font(.subheadline.weight(station != nil ? .semibold : .regular))
                    .foregroundColor(station != nil ? AppTheme.inkAdaptive(colorScheme) : AppTheme.mutedAdaptive(colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.hairlineStrong)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(station.map { "\(placeholder): \($0.longName). Tippen zum Ändern." } ?? "\(placeholder). Tippen zum Auswählen.")
    }

    // MARK: - Collapsed Header Content

    private var collapsedHeaderContent: some View {
        HStack(spacing: 10) {
            if let start = selectedStartStation, let end = selectedEndStation {
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(Color(red: 0.2, green: 0.85, blue: 0.45))
                    Text(start.longName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                        .lineLimit(1)
                        .frame(maxWidth: 110, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.muted)
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.35))
                    Text(end.longName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                        .lineLimit(1)
                        .frame(maxWidth: 110, alignment: .leading)
                }
            } else {
                Text("Verbindungen")
                    .font(AppTheme.displayFont(size: 16))
                    .foregroundColor(AppTheme.inkAdaptive(colorScheme))
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(Color(red: 0.2, green: 0.9, blue: 0.5).opacity(0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulseScale)
                Circle()
                    .fill(Color(red: 0.2, green: 0.9, blue: 0.5))
                    .frame(width: 6, height: 6)
            }
            .accessibilityHidden(true)

            TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                Text(Self.headerTimeFormatter.string(from: timeline.date))
                    .font(AppTheme.monoFont(size: 13))
                    .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                    .contentTransition(.numericText())
            }
            .accessibilityHidden(true)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(AppTheme.surfaceStrongAdaptive(colorScheme))
                    .overlay(Capsule().stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
            )
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Formatters

    private static let headerTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d. MMM"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    private static var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Guten Morgen"
        case 12..<17: return "Guten Tag"
        case 17..<21: return "Guten Abend"
        default: return "Gute Nacht"
        }
    }

    // MARK: - Filtered Trips

    private var filteredTrips: [DetailedTrip] {
        var trips = graphQLService.detailedTrips

        if showDelaysOnly {
            trips = trips.filter { trip in
                trip.legs.contains { leg in
                    guard leg.isTimedLeg,
                          let timetabled = leg.departureTime,
                          let estimated = leg.estimatedDepartureTime else { return false }
                    return (formatter.calculateDelay(timetabled: timetabled, estimated: estimated) ?? 0) > 0
                }
            }
        }

        if !enableTram || !enableBus || !enableSBahn {
            trips = trips.filter { trip in
                trip.legs.filter { $0.isTimedLeg }.allSatisfy { leg in
                    let type = (leg.serviceType ?? "").uppercased()
                    if type.contains("STRASSENBAHN") || type.contains("TRAM") { return enableTram }
                    else if type.contains("S_BAHN") || type.contains("SBAHN") || type.contains("SUBURBAN") { return enableSBahn }
                    else if type.contains("BUS") { return enableBus }
                    return true
                }
            }
        }

        return trips.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.primaryColor))
                .scaleEffect(1.5)
            Text("Verbindung wird hergestellt...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verbindung wird hergestellt")
    }

    // MARK: - Manual Login View

    private var manualLoginView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(AppTheme.surfaceStrong)
                    .frame(width: 100, height: 100)
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.muted)
            }
            VStack(spacing: 6) {
                Text("Verbindung fehlgeschlagen")
                    .font(.title3).fontWeight(.bold)
                Text("Bitte erneut versuchen")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Button(action: { Task { await authService.authenticate() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Erneut verbinden")
                }
                .font(AppTheme.buttonFont)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(AppTheme.primary))
            }
            .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 14) {
            searchActionsCard

            if sameStationValidationError {
                errorBanner(message: "Start und Ziel dürfen nicht identisch sein.")
            } else if let error = graphQLService.lastError {
                errorBanner(message: error.message)
            }

            if graphQLService.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.primaryColor))
                    .scaleEffect(1.3)
                    .padding(.vertical, 30)
            }

            if !hasSearchedOnce && !graphQLService.isLoading {
                emptyStateView
            }

            if hasSearchedOnce && !graphQLService.isLoading {
                navigationButton(earlier: true)
            }

            if !filteredTrips.isEmpty {
                connectionsList
            } else if !graphQLService.detailedTrips.isEmpty && showDelaysOnly {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Keine verspäteten Verbindungen.")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.1)))
                .padding(.horizontal)
            }

            if hasSearchedOnce && !graphQLService.isLoading {
                navigationButton(earlier: false)
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange).font(.system(size: 16))
            Text(message)
                .font(.subheadline).foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.18), lineWidth: 1))
        )
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fehler: \(message)")
    }

    // MARK: - Search Actions Card

    private var searchActionsCard: some View {
        VStack(spacing: 0) {
            // Time mode picker
            Picker("", selection: $tripTimeMode) {
                Text("Jetzt").tag(TripTimeMode.now)
                Text("Abfahrt").tag(TripTimeMode.departure)
                Text("Ankunft").tag(TripTimeMode.arrival)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if tripTimeMode != .now {
                Divider().padding(.horizontal, 16)

                DatePicker(
                    "", selection: $selectedDateTime,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .accessibilityLabel(tripTimeMode == .arrival ? "Ankunftszeit auswählen" : "Abfahrtszeit auswählen")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if selectedStartStation != nil && selectedEndStation != nil {
                Divider().padding(.horizontal, 16)

                Button(action: {
                    HapticHelper.impact(.medium)
                    Task { await searchConnections() }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                        Text("Verbindungen suchen")
                            .font(AppTheme.buttonFont)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(AppTheme.primary)
                    )
                }
                .accessibilityHint("Sucht Verbindungen zwischen Start und Ziel")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                .shadow(color: AppTheme.shadowColor(), radius: 10, y: 4)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tripTimeMode != .now)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedStartStation != nil && selectedEndStation != nil)
        .padding(.horizontal)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "tram.fill")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.mutedSoft)
                .accessibilityHidden(true)
            VStack(spacing: 5) {
                Text("Wohin möchtest du fahren?")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Wähle Start und Ziel oben, um Verbindungen zu finden.")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal)
    }

    // MARK: - Connections List

    private var connectionsList: some View {
        VStack(spacing: 12) {
            ForEach(filteredTrips) { trip in
                Button {
                    guard !trip.legs.isEmpty else { return }
                    selectedTrip = trip
                } label: {
                    TripCard(trip: trip)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Navigation Buttons (Earlier / Later)

    private func navigationButton(earlier: Bool) -> some View {
        Button {
            HapticHelper.impact(.light)
            Task {
                if earlier { await loadEarlierConnections() }
                else { await loadLaterConnections() }
            }
        } label: {
            HStack(spacing: 6) {
                if earlier {
                    Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
                }
                Text(earlier ? "Frühere Verbindungen" : "Spätere Verbindungen")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if !earlier {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(AppTheme.surfaceStrongAdaptive(colorScheme))
                    .overlay(Capsule().stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
            )
            .foregroundColor(AppTheme.muted)
        }
        .disabled(graphQLService.isLoading)
        .accessibilityHint(earlier ? "Lädt Verbindungen eine Stunde früher" : "Lädt Verbindungen eine Stunde später")
        .padding(.horizontal)
        .padding(.bottom, earlier ? 0 : 8)
    }

    // MARK: - Search Logic

    private func resolveStations() -> (Station, Station)? {
        guard let start = selectedStartStation, let end = selectedEndStation else { return nil }
        return (start, end)
    }

    private func searchConnections() async {
        guard let (startStation, endStation) = resolveStations() else { return }

        if startStation.globalID == endStation.globalID {
            sameStationValidationError = true
            return
        }
        sameStationValidationError = false

        if !authService.isTokenValid { await authService.autoAuthenticate() }
        guard let token = authService.accessToken, !token.isEmpty else { return }

        let searchDate = tripTimeMode == .now ? Date() : selectedDateTime
        currentSearchTime = searchDate
        hasSearchedOnce = true
        let iso = ISO8601DateFormatter().string(from: searchDate)

        await graphQLService.getConnections(
            fromGlobalID: startStation.globalID,
            toGlobalID: endStation.globalID,
            accessToken: token,
            departureTime: tripTimeMode != .arrival ? iso : nil,
            arrivalTime: tripTimeMode == .arrival ? iso : nil
        )
        Task { await graphQLService.enrichConnectionsWithOccupancy(accessToken: token) }
    }

    private func loadEarlierConnections() async {
        guard let (startStation, endStation) = resolveStations() else { return }
        if !authService.isTokenValid { await authService.autoAuthenticate() }
        guard let token = authService.accessToken, !token.isEmpty else { return }

        let earlierTime: Date
        if let firstTrip = graphQLService.detailedTrips.first,
           let firstDep = formatter.parseISO8601(firstTrip.startTime) {
            earlierTime = firstDep.addingTimeInterval(-3600)
        } else {
            earlierTime = currentSearchTime.addingTimeInterval(-3600)
        }
        currentSearchTime = earlierTime

        await graphQLService.getConnections(
            fromGlobalID: startStation.globalID,
            toGlobalID: endStation.globalID,
            accessToken: token,
            departureTime: ISO8601DateFormatter().string(from: earlierTime),
            mode: .prepend
        )
        Task { await graphQLService.enrichConnectionsWithOccupancy(accessToken: token) }
    }

    private func loadLaterConnections() async {
        guard let (startStation, endStation) = resolveStations() else { return }
        if !authService.isTokenValid { await authService.autoAuthenticate() }
        guard let token = authService.accessToken, !token.isEmpty else { return }

        let laterTime: Date
        if let lastTrip = graphQLService.detailedTrips.last,
           let lastDep = formatter.parseISO8601(lastTrip.startTime) {
            laterTime = lastDep.addingTimeInterval(60)
        } else {
            laterTime = currentSearchTime.addingTimeInterval(3600)
        }
        currentSearchTime = laterTime

        await graphQLService.getConnections(
            fromGlobalID: startStation.globalID,
            toGlobalID: endStation.globalID,
            accessToken: token,
            departureTime: ISO8601DateFormatter().string(from: laterTime),
            mode: .append
        )
        Task { await graphQLService.enrichConnectionsWithOccupancy(accessToken: token) }
    }
}

// MARK: - Trip Time Mode

enum TripTimeMode {
    case now, departure, arrival
}

// MARK: - Preference Key for Scroll Offset

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    ConnectionsView(
        authService: AuthService(),
        graphQLService: GraphQLService(),
        locationManager: LocationManager()
    )
    .environmentObject(LiveActivityManager())
}
