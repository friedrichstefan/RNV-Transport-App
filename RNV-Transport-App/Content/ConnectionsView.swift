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

    @StateObject private var liveActivityManager = LiveActivityManager()

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
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollOffsetTask: Task<Void, Never>?

    @Environment(\.colorScheme) private var colorScheme

    private let maxHeaderHeight: CGFloat = 120
    private let minHeaderHeight: CGFloat = 60
    private let scrollThreshold: CGFloat = 80
    private let formatter = DateFormattingHelper.shared

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color(colorScheme == .dark ? .black : .systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    RNVScrollableHeaderView(scrollOffset: scrollOffset)
                        .zIndex(1)

                    GeometryReader { geometry in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                Color.clear
                                    .frame(height: getCurrentHeaderHeight())

                                VStack(spacing: 20) {
                                    if authService.isAuthenticating {
                                        loadingView
                                    } else if authService.isAuthenticated {
                                        mainContent
                                    } else {
                                        manualLoginView
                                    }
                                }
                                .padding(.top, 10)
                            }
                            .background(
                                GeometryReader { scrollGeometry in
                                    Color.clear
                                        .onChange(of: scrollGeometry.frame(in: .global).minY) { newValue in
                                            let newOffset = max(0, -newValue)
                                            // Throttle: nur updaten wenn Änderung > 1pt – verhindert
                                            // "action tried to update multiple times per frame" Warnung
                                            guard abs(newOffset - scrollOffset) > 1.0 else { return }
                                            scrollOffset = newOffset
                                        }
                                }
                            )
                        }
                        .coordinateSpace(name: "scroll")
                    }
                }
            }
            .navigationTitle("")
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
        }
    }

    // MARK: - Filtered Trips

    private var filteredTrips: [DetailedTrip] {
        var trips = graphQLService.detailedTrips

        // Nur Trips mit Verspätung anzeigen
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

        // Verkehrsmittelfilter
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

        // Max. Anzahl Verbindungen begrenzen
        return Array(trips.prefix(maxConnections))
    }

    // MARK: - Header Height Calculation

    private func getCurrentHeaderHeight() -> CGFloat {
        let progress = min(max(scrollOffset / scrollThreshold, 0), 1)
        return maxHeaderHeight - (progress * (maxHeaderHeight - minHeaderHeight))
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)

            Text("Anmeldung läuft...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Manual Login View

    private var manualLoginView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Anmeldung fehlgeschlagen")
                .font(.title2)
                .fontWeight(.bold)

            Text("Bitte erneut versuchen")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: {
                Task {
                    await authService.authenticate()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Erneut anmelden")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue)
                )
            }
            .padding(.horizontal, 40)
        }
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
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1.5)
                    .padding()
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
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.15))
        )
        .padding(.horizontal)
    }

    // MARK: - Search Card

    private var searchCard: some View {
        VStack(spacing: 16) {
            StationSelectButton(
                icon: "circle.fill",
                iconColor: .green,
                title: "Start",
                station: selectedStartStation,
                action: {
                    isPickingStartStation = true
                    showingStationPicker = true
                }
            )

            HStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 2, height: 30)
                    .padding(.leading, 19)
                Spacer()
            }

            StationSelectButton(
                icon: "location.fill",
                iconColor: .red,
                title: "Ziel",
                station: selectedEndStation,
                action: {
                    isPickingStartStation = false
                    showingStationPicker = true
                }
            )

            VStack(spacing: 12) {
                HStack {
                    Toggle("Geplante Abfahrt", isOn: $useCustomTime)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()
                }

                if useCustomTime {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.clock")
                            .foregroundColor(.blue)
                            .font(.system(size: 20))

                        DatePicker(
                            "Abfahrtszeit",
                            selection: $selectedDateTime,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
            }

            if selectedStartStation != nil && selectedEndStation != nil {
                Button(action: {
                    Task {
                        await searchConnections()
                    }
                }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text(useCustomTime ? "Geplante Verbindung suchen" : "Verbindung suchen")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                .padding(.top, 8)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 10, y: 5)
        )
        .padding(.horizontal)
    }

    // MARK: - Connections List

    private var connectionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verbindungen")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.horizontal)

            ForEach(filteredTrips) { trip in
                TripCard(
                    trip: trip,
                    graphQLService: graphQLService,
                    authService: authService,
                    liveActivityManager: liveActivityManager
                )
                .onTapGesture {
                    guard !trip.legs.isEmpty else {
                        print("⚠️ [WARNING] Trip hat keine Legs")
                        return
                    }
                    selectedTrip = trip
                }
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Search

    private func searchConnections() async {
        guard let startStation = selectedStartStation,
              let endStation = selectedEndStation else { return }

        let departureTime = useCustomTime ? selectedDateTime : Date()

        await graphQLService.getConnections(
            fromGlobalID: startStation.globalID,
            toGlobalID: endStation.globalID,
            accessToken: authService.accessToken ?? "",
            departureTime: ISO8601DateFormatter().string(from: departureTime)
        )
    }
}

// MARK: - Header View

struct RNVScrollableHeaderView: View {
    let scrollOffset: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private let maxHeaderHeight: CGFloat = 100
    private let minHeaderHeight: CGFloat = 50
    private let scrollThreshold: CGFloat = 80

    var body: some View {
        let progress = min(max(scrollOffset / scrollThreshold, 0), 1)
        let currentHeight = maxHeaderHeight - (progress * (maxHeaderHeight - minHeaderHeight))
        let logoSize = 50 - (progress * 20)
        let fontSize = 14 - (progress * 3)

        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(Color(red: 0/255, green: 43/255, blue: 78/255))
                    .ignoresSafeArea(.all, edges: .all)
                    .frame(height: currentHeight)

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 30)

                    HStack(alignment: .center, spacing: max(6, 12 - (progress * 6))) {
                        HStack(spacing: max(4, 8 - (progress * 4))) {
                            Image("rnv-logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: logoSize, height: logoSize)
                                .animation(.easeInOut(duration: 0.3), value: logoSize)

                            if progress < 0.7 {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Rhein-Neckar-Verkehr")
                                        .font(.system(size: fontSize, weight: .semibold))
                                        .foregroundColor(.white)
                                        .opacity(1 - progress)

                                    Text("Ihre ÖPNV-App")
                                        .font(.system(size: max(6, fontSize - 3), weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .opacity(1 - progress)
                                }
                                .animation(.easeInOut(duration: 0.3), value: progress)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: max(0, 2 - progress)) {
                            TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                                Text(getCurrentTime(timeline.date))
                                    .font(.system(size: max(12, 20 - (progress * 6)),
                                                weight: .bold,
                                                design: .monospaced))
                                    .foregroundColor(.white)
                            }

                            if progress < 0.8 {
                                HStack(spacing: max(2, 4 - (progress * 2))) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: max(3, 6 - (progress * 3)),
                                              height: max(3, 6 - (progress * 3)))

                                    Text("LIVE • \(getCurrentDate())")
                                        .font(.system(size: max(6, 8 - (progress * 2)), weight: .semibold))
                                        .foregroundColor(.white.opacity(0.9))
                                        .textCase(.uppercase)
                                        .opacity(1 - progress)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, max(8, 14 - (progress * 6)))
                    .padding(.bottom, 15)

                    Spacer()
                }
                .frame(maxHeight: currentHeight + 50)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.1), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 2)
        }
        .frame(height: currentHeight)
        .animation(.easeInOut(duration: 0.3), value: currentHeight)
    }

    private func getCurrentTime(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }

    private func getCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: Date())
    }
}

// MARK: - Station Select Button

struct StationSelectButton: View {
    let icon: String
    let iconColor: Color
    let title: String
    let station: Station?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(iconColor.opacity(colorScheme == .dark ? 0.3 : 0.15))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(station?.longName ?? "Haltestelle wählen")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(colorScheme == .dark ? .systemGray5 : .secondarySystemGroupedBackground))
            )
        }
    }
}

#Preview {
    ConnectionsView(
        authService: AuthService(),
        graphQLService: GraphQLService(),
        locationManager: LocationManager()
    )
}
