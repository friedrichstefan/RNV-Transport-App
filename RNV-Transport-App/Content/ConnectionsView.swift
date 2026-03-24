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
    @State private var useCustomTime = false
    @State private var currentSearchTime: Date = Date()
    @State private var hasSearchedOnce: Bool = false
    @State private var scrollOffset: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    private let formatter = DateFormattingHelper.shared

    // Header-Dimensionen
    private let maxHeaderHeight: CGFloat = 200
    private let minHeaderHeight: CGFloat = 60

    /// Fortschritt des Zusammenklappens: 0 = voll offen, 1 = komplett eingeklappt
    private var collapseProgress: CGFloat {
        min(1, max(0, scrollOffset / (maxHeaderHeight - minHeaderHeight)))
    }

    /// Aktuelle Header-Höhe
    private var currentHeaderHeight: CGFloat {
        max(minHeaderHeight, maxHeaderHeight - scrollOffset)
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                // MARK: - ScrollView mit Content
                ScrollView {
                    VStack(spacing: 0) {
                        // Platzhalter für den Header
                        Color.clear
                            .frame(height: maxHeaderHeight + 20)

                        // MARK: - Content
                        VStack(spacing: 20) {
                            if authService.isAuthenticating {
                                loadingView
                            } else if authService.isAuthenticated {
                                mainContent
                            } else {
                                manualLoginView
                            }
                        }
                        .padding(.bottom, 30)
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: -geo.frame(in: .named("scroll")).origin.y
                            )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = max(0, value)
                }

                // MARK: - Collapsing Hero Header (sticky)
                collapsingHeader
                    .zIndex(1)
            }
            .background(
                Color(colorScheme == .dark ? .black : .systemGroupedBackground)
                    .ignoresSafeArea()
            )
            .navigationBarHidden(true)
            .sheet(isPresented: $showingStationPicker) {
                StationPickerView(
                    authService: authService,
                    graphQLService: graphQLService,
                    locationManager: locationManager,
                    selectedStation: isPickingStartStation ? $selectedStartStation : $selectedEndStation
                )
            }
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
            ZStack {
                // MARK: Mehrschichtiger Premium-Gradient
                headerGradientBackground

                // MARK: Stilisierte Transit-Linien (Hintergrundmuster)
                headerTransitPattern
                    .opacity(Double(1.0 - collapseProgress))

                // MARK: Subtiler Licht-Akzent oben rechts
                headerGlowAccent

                // MARK: Header-Inhalt
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    // Expanded Content (blendet aus beim Scrollen)
                    if collapseProgress < 0.95 {
                        expandedHeaderContent
                            .opacity(Double(1.0 - collapseProgress * 1.4))
                            .scaleEffect(1.0 - collapseProgress * 0.05, anchor: .topLeading)
                    }

                    // Collapsed Content (blendet ein beim Scrollen)
                    if collapseProgress > 0.3 {
                        collapsedHeaderContent
                            .opacity(Double(min(1.0, (collapseProgress - 0.3) / 0.35)))
                    }
                }
            }
            .frame(height: currentHeaderHeight)
            .clipShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 32 * (1 - collapseProgress),
                    bottomTrailingRadius: 32 * (1 - collapseProgress)
                )
            )
            .shadow(color: Color(red: 0.0, green: 0.2, blue: 0.3).opacity(0.3), radius: 16, y: 8)
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .background(
            Color(red: 0.02, green: 0.05, blue: 0.14)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Header Gradient Background

    private var headerGradientBackground: some View {
        ZStack {
            // Basis-Gradient: Tiefes Dunkelblau → Teal
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.02, green: 0.05, blue: 0.14), location: 0.0),
                    .init(color: Color(red: 0.01, green: 0.14, blue: 0.24), location: 0.35),
                    .init(color: Color(red: 0.0, green: 0.28, blue: 0.36), location: 0.65),
                    .init(color: Color(red: 0.0, green: 0.38, blue: 0.42), location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Sekundärer Akzent-Gradient: Violetter Schimmer
            RadialGradient(
                colors: [
                    Color(red: 0.2, green: 0.1, blue: 0.4).opacity(0.25),
                    Color.clear,
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 200
            )

            // Warmem Akzent unten links
            RadialGradient(
                colors: [
                    Color(red: 0.0, green: 0.5, blue: 0.5).opacity(0.15),
                    Color.clear,
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 180
            )
        }
    }

    // MARK: - Header Transit Pattern (stilisierte Linien)

    private var headerTransitPattern: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Geschwungene Linie 1 (große Route)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.1, y: h * 0.85))
                    path.addCurve(
                        to: CGPoint(x: w * 0.95, y: h * 0.15),
                        control1: CGPoint(x: w * 0.35, y: h * 0.6),
                        control2: CGPoint(x: w * 0.65, y: h * 0.1)
                    )
                }
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.0), Color.white.opacity(0.06), Color.white.opacity(0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )

                // Geschwungene Linie 2 (parallel, versetzt)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.15, y: h * 0.95))
                    path.addCurve(
                        to: CGPoint(x: w * 1.0, y: h * 0.25),
                        control1: CGPoint(x: w * 0.4, y: h * 0.7),
                        control2: CGPoint(x: w * 0.7, y: h * 0.2)
                    )
                }
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.0), Color.white.opacity(0.04), Color.white.opacity(0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )

                // Haltestellen-Punkte entlang der Route
                ForEach(0..<4, id: \.self) { i in
                    let t = CGFloat(i + 1) / 5.0
                    let x = curvePoint(t: t, p0: w * 0.1, p1: w * 0.35, p2: w * 0.65, p3: w * 0.95)
                    let y = curvePoint(t: t, p0: h * 0.85, p1: h * 0.6, p2: h * 0.1, p3: h * 0.15)
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 4, height: 4)
                        .position(x: x, y: y)
                }

                // Dezente horizontale Netzlinien
                ForEach(0..<3, id: \.self) { i in
                    let yPos = h * CGFloat(i + 1) / 4.0
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: yPos))
                        path.addLine(to: CGPoint(x: w, y: yPos))
                    }
                    .stroke(Color.white.opacity(0.02), lineWidth: 0.5)
                }
            }
        }
    }

    /// Kubische Bézier-Interpolation für einen Punkt
    private func curvePoint(t: CGFloat, p0: CGFloat, p1: CGFloat, p2: CGFloat, p3: CGFloat) -> CGFloat {
        let mt = 1 - t
        return mt * mt * mt * p0 + 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t * p3
    }

    // MARK: - Header Glow Accent

    private var headerGlowAccent: some View {
        GeometryReader { geo in
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.0, green: 0.6, blue: 0.7).opacity(0.12),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .position(x: geo.size.width * 0.85, y: geo.size.height * 0.2)
                .blur(radius: 20)
        }
    }

    // MARK: - Expanded Header Content

    private var expandedHeaderContent: some View {
        VStack(spacing: 16) {
            // Obere Zeile: Logo/Grußzeile + Uhr
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.greetingText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(0.3)

                    Text("Wohin geht's?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: Color(red: 0.0, green: 0.4, blue: 0.5).opacity(0.4), radius: 12, y: 2)
                }

                Spacer()

                // Uhr-Badge mit Glassmorphism
                VStack(alignment: .trailing, spacing: 3) {
                    TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                        Text(Self.headerTimeFormatter.string(from: timeline.date))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }

                    Text(Self.headerDateFormatter.string(from: Date()))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(0.5)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial.opacity(0.5))
                        .environment(\.colorScheme, .dark)
                )
            }

            // Untere Zeile: Status-Chips mit Glassmorphism
            HStack(spacing: 8) {
                // Region-Chip
                HStack(spacing: 5) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Rhein-Neckar")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.6))
                        .environment(\.colorScheme, .dark)
                )

                // Echtzeit-Chip mit pulsierendem Dot
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.2, green: 0.9, blue: 0.5))
                            .frame(width: 6, height: 6)
                        Circle()
                            .fill(Color(red: 0.2, green: 0.9, blue: 0.5).opacity(0.4))
                            .frame(width: 10, height: 10)
                    }
                    Text("Echtzeit")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.3, green: 0.95, blue: 0.6))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(red: 0.2, green: 0.9, blue: 0.5).opacity(0.1))
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 0.2, green: 0.9, blue: 0.5).opacity(0.15), lineWidth: 0.5)
                        )
                )

                Spacer()

                // Aktive Fahrten Indikator (wenn vorhanden)
                let activeCount = LiveActivityState.shared.getAllActiveTrips().count
                if activeCount > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 9))
                        Text("\(activeCount) aktiv")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.3))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(Color.orange.opacity(0.15), lineWidth: 0.5)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Collapsed Header Content

    private var collapsedHeaderContent: some View {
        HStack(spacing: 12) {
            Text("Wohin geht's?")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            // Kompakte Uhr
            TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                Text(Self.headerTimeFormatter.string(from: timeline.date))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.4))
                    .environment(\.colorScheme, .dark)
            )

            // Echtzeit-Dot
            ZStack {
                Circle()
                    .fill(Color(red: 0.2, green: 0.9, blue: 0.5))
                    .frame(width: 7, height: 7)
                Circle()
                    .fill(Color(red: 0.2, green: 0.9, blue: 0.5).opacity(0.3))
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // Static formatters & helpers for header
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
        case 5..<12: return "Guten Morgen ☀️"
        case 12..<17: return "Guten Tag 👋"
        case 17..<21: return "Guten Abend 🌆"
        default: return "Gute Nacht 🌙"
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
                    if type.contains("STRASSENBAHN") || type.contains("TRAM") {
                        return enableTram
                    } else if type.contains("S_BAHN") || type.contains("SBAHN") || type.contains("SUBURBAN") {
                        return enableSBahn
                    } else if type.contains("BUS") {
                        return enableBus
                    }
                    return true
                }
            }
        }

        return Array(trips.prefix(maxConnections))
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
    }

    // MARK: - Manual Login View

    private var manualLoginView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(AppTheme.primaryColor.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.accentGradient)
            }

            VStack(spacing: 6) {
                Text("Verbindung fehlgeschlagen")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Bitte erneut versuchen")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button(action: {
                Task { await authService.authenticate() }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Erneut verbinden")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppTheme.accentGradient)
                )
            }
            .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 20) {
            searchCard

            if let error = graphQLService.lastError {
                errorBanner(message: error.message)
            }

            if graphQLService.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.primaryColor))
                    .scaleEffect(1.3)
                    .padding(.vertical, 30)
            }

            if hasSearchedOnce && !graphQLService.isLoading {
                earlierButton
            }

            if !filteredTrips.isEmpty {
                connectionsList
            } else if !graphQLService.detailedTrips.isEmpty && showDelaysOnly {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Keine verspäteten Verbindungen gefunden.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.1)))
                .padding(.horizontal)
            }

            if hasSearchedOnce && !graphQLService.isLoading {
                laterButton
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 18))
            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }

    // MARK: - Search Card

    private var searchCard: some View {
        VStack(spacing: 0) {
            // Station inputs
            VStack(spacing: 0) {
                stationInputRow(
                    icon: "circle.fill",
                    iconColor: Color(red: 0.2, green: 0.8, blue: 0.4),
                    title: "Von",
                    station: selectedStartStation,
                    action: {
                        isPickingStartStation = true
                        showingStationPicker = true
                    }
                )

                // Divider mit Swap-Button
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 1)

                    Button {
                        HapticHelper.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            let temp = selectedStartStation
                            selectedStartStation = selectedEndStation
                            selectedEndStation = temp
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(colorScheme == .dark ? .systemGray5 : .systemBackground))
                                .frame(width: 36, height: 36)
                                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AppTheme.primaryColor)
                        }
                    }
                    .disabled(selectedStartStation == nil && selectedEndStation == nil)
                    .opacity((selectedStartStation == nil && selectedEndStation == nil) ? 0.35 : 1.0)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 1)
                }
                .padding(.horizontal, 16)

                stationInputRow(
                    icon: "mappin.circle.fill",
                    iconColor: Color(red: 0.9, green: 0.3, blue: 0.3),
                    title: "Nach",
                    station: selectedEndStation,
                    action: {
                        isPickingStartStation = false
                        showingStationPicker = true
                    }
                )
            }

            // Trennlinie
            Rectangle()
                .fill(Color.secondary.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Time picker
            VStack(spacing: 10) {
                HStack {
                    Toggle(isOn: $useCustomTime) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(AppTheme.primaryColor)
                                .font(.system(size: 13))
                            Text("Geplante Abfahrt")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .tint(AppTheme.primaryColor)
                }
                .padding(.horizontal, 16)

                if useCustomTime {
                    DatePicker(
                        "Abfahrtszeit",
                        selection: $selectedDateTime,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppTheme.primaryColor.opacity(0.06))
                    )
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 16)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: useCustomTime)

            // Search button
            if selectedStartStation != nil && selectedEndStation != nil {
                Button(action: {
                    HapticHelper.impact(.medium)
                    Task { await searchConnections() }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .bold))
                        Text("Verbindung suchen")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(AppTheme.accentGradient)
                            // Subtiler Glanz-Effekt oben
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.15), Color.clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                    )
                    .shadow(color: AppTheme.primaryColor.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedStartStation != nil && selectedEndStation != nil)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.06), radius: 16, y: 8)
                .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        )
        .padding(.horizontal)
    }

    @ViewBuilder
    private func stationInputRow(icon: String, iconColor: Color, title: String, station: Station?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 12))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(iconColor.opacity(colorScheme == .dark ? 0.18 : 0.1))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Text(station?.longName ?? "Haltestelle wählen")
                        .font(.system(size: 16, weight: station != nil ? .semibold : .regular))
                        .foregroundColor(station != nil ? .primary : .secondary.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Connections List

    private var connectionsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Verbindungen")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(filteredTrips.count) Ergebnisse")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
            .padding(.horizontal)

            ForEach(filteredTrips) { trip in
                TripCard(
                    trip: trip,
                    graphQLService: graphQLService,
                    authService: authService,
                    liveActivityManager: liveActivityManager
                )
                .onTapGesture {
                    guard !trip.legs.isEmpty else { return }
                    selectedTrip = trip
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Earlier / Later Buttons

    private var earlierButton: some View {
        Button {
            Task { await loadEarlierConnections() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                Text("Frühere Verbindungen")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(colorScheme == .dark ? .systemGray5 : .systemGray6))
            )
            .foregroundColor(.primary)
        }
        .disabled(graphQLService.isLoading)
        .padding(.horizontal)
    }

    private var laterButton: some View {
        Button {
            Task { await loadLaterConnections() }
        } label: {
            HStack(spacing: 6) {
                Text("Spätere Verbindungen")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.primaryColor.opacity(0.1))
            )
            .foregroundColor(AppTheme.primaryColor)
        }
        .disabled(graphQLService.isLoading)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Search

    private func searchConnections() async {
        guard let startStation = selectedStartStation,
              let endStation = selectedEndStation else { return }

        if !authService.isTokenValid {
            await authService.autoAuthenticate()
        }
        guard let token = authService.accessToken, !token.isEmpty else { return }

        let departureTime = useCustomTime ? selectedDateTime : Date()
        currentSearchTime = departureTime
        hasSearchedOnce = true

        await graphQLService.getConnections(
            fromGlobalID: startStation.globalID,
            toGlobalID: endStation.globalID,
            accessToken: token,
            departureTime: ISO8601DateFormatter().string(from: departureTime)
        )
    }

    private func loadEarlierConnections() async {
        guard let startStation = selectedStartStation,
              let endStation = selectedEndStation else { return }

        if !authService.isTokenValid {
            await authService.autoAuthenticate()
        }
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
            departureTime: ISO8601DateFormatter().string(from: earlierTime)
        )
    }

    private func loadLaterConnections() async {
        guard let startStation = selectedStartStation,
              let endStation = selectedEndStation else { return }

        if !authService.isTokenValid {
            await authService.autoAuthenticate()
        }
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
            departureTime: ISO8601DateFormatter().string(from: laterTime)
        )
    }
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
