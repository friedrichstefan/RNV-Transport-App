//
//  StationPickerView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 09.01.26.
//

import SwiftUI
import CoreLocation
import MapKit

private enum GeocodeError: LocalizedError {
    case noResultsFound
    var errorDescription: String? { "Keine Ergebnisse für diese Haltestelle gefunden." }
}

struct StationPickerView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var graphQLService: GraphQLService
    @ObservedObject var locationManager: LocationManager
    @Binding var selectedStation: Station?
    @Binding var selectedDate: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var hasLoadedStations = false
    @State private var searchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var recentStations: [Station] = []
    @State private var showNearbyMap = false
    @FocusState private var isSearchFocused: Bool

    // Kürzeres Debounce für schnelleres Feedback
    private let debounceMilliseconds: UInt64 = 300

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.canvasAdaptive(colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // MARK: - Search Bar
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    // MARK: - Content
                    if graphQLService.isLoading && !hasLoadedStations {
                        loadingView
                    } else if searchText.isEmpty {
                        quickActionsView
                    } else if graphQLService.isLoading {
                        VStack(spacing: 0) {
                            inlineLoadingIndicator
                            if !graphQLService.stations.isEmpty {
                                stationList
                            }
                        }
                    } else if graphQLService.stations.isEmpty && hasLoadedStations {
                        emptyStateView
                    } else {
                        stationList
                    }
                }
            }
            .navigationTitle("Haltestelle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.primaryColor)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isSearchFocused = true
            }
            loadRecentStations()
        }
        .onChange(of: searchText) { _, newValue in
            handleSearchTextChange(newValue)
        }
        .onDisappear {
            searchDebounceTask?.cancel()
        }
        .sheet(isPresented: $showNearbyMap) {
            if let location = locationManager.location,
               let accessToken = authService.accessToken {
                NearbyStationMapSheet(
                    graphQLService: graphQLService,
                    userLocation: location,
                    accessToken: accessToken
                ) { station in
                    selectAndDismiss(station)
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 15, weight: .medium))

                TextField("Haltestelle suchen...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        searchDebounceTask?.cancel()
                        Task { await searchStations(query: searchText) }
                    }

                if !searchText.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            searchText = ""
                            graphQLService.stations = []
                            hasLoadedStations = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.6))
                            .font(.system(size: 16))
                    }
                    .transition(.opacity.combined(with: .scale))
                }

                if graphQLService.isLoading && !searchText.isEmpty {
                    ProgressView()
                        .scaleEffect(0.7)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.surfaceCardAdaptive(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSearchFocused ? AppTheme.primary.opacity(0.5) : AppTheme.hairlineAdaptive(colorScheme),
                        lineWidth: isSearchFocused ? 1.5 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
            .animation(.easeInOut(duration: 0.15), value: searchText.isEmpty)
        }
    }

    // MARK: - Quick Actions (leerer Suchtext)

    private var quickActionsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Datum & Uhrzeit
                dateTimeSection

                // Standort-Buttons
                if locationManager.location != nil {
                    Button {
                        loadNearbyStations()
                        showNearbyMap = true
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.surfaceStrongAdaptive(colorScheme))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "map.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppTheme.primaryColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("In der Nähe")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("Haltestellen auf der Karte auswählen")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
                    )
                }

                // Zuletzt verwendet
                if !recentStations.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text("Zuletzt verwendet")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.3)
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(recentStations.prefix(5).enumerated()), id: \.element.id) { index, station in
                                Button {
                                    selectAndDismiss(station)
                                } label: {
                                    stationRowContent(station: station)
                                }
                                .buttonStyle(.plain)

                                if index < min(recentStations.count - 1, 4) {
                                    Divider()
                                        .padding(.leading, 52)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
                        )
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Date & Time Section

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Abfahrtzeit")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.3)
            }
            .padding(.horizontal, 4)

            HStack {
                DatePicker("", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(AppTheme.primaryColor)
                Spacer()
                if !Calendar.current.isDateInToday(selectedDate) {
                    Button("Zurücksetzen") { selectedDate = Date() }
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Inline Loading Indicator

    private var inlineLoadingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Suche...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.primaryColor))
                .scaleEffect(1.3)
            Text("Suche Haltestellen...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Station List

    private var stationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Ergebnis-Header
                HStack {
                    Text("\(graphQLService.stations.count) Ergebnis\(graphQLService.stations.count == 1 ? "" : "se")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.3)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ForEach(Array(graphQLService.stations.enumerated()), id: \.element.id) { index, station in
                    Button {
                        selectAndDismiss(station)
                    } label: {
                        stationRowContent(station: station)
                    }
                    .buttonStyle(StationRowButtonStyle())

                    if index < graphQLService.stations.count - 1 {
                        Divider()
                            .padding(.leading, 68)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
                    .padding(.horizontal, 16)
            )
            .padding(.bottom, 30)
        }
    }

    // MARK: - Station Row Content

    @ViewBuilder
    private func stationRowContent(station: Station) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.surfaceStrongAdaptive(colorScheme))
                    .frame(width: 36, height: 36)
                Image(systemName: "tram.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.primaryColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(station.longName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.06))
                    .frame(width: 80, height: 80)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .thin))
                    .foregroundColor(.secondary.opacity(0.4))
            }

            Text("Keine Ergebnisse")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Versuche einen anderen Suchbegriff\noder prüfe die Schreibweise")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Search Logic

    private func handleSearchTextChange(_ newValue: String) {
        searchDebounceTask?.cancel()

        guard !newValue.isEmpty else {
            graphQLService.stations = []
            hasLoadedStations = false
            return
        }

        let delay: UInt64 = newValue.count >= 3 ? debounceMilliseconds : 500

        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: delay * 1_000_000)
            guard !Task.isCancelled else { return }
            await searchStations(query: newValue)
        }
    }

    private func searchStations(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let accessToken = authService.accessToken else {
            graphQLService.stations = []
            hasLoadedStations = true
            return
        }

        hasLoadedStations = true

        await graphQLService.searchStationsByName(
            name: query,
            accessToken: accessToken
        )

        #if DEBUG
        print("🔍 [StationPicker] Suche '\(query)' → \(graphQLService.stations.count) Ergebnisse")
        for station in graphQLService.stations.prefix(3) {
            print("   • \(station.longName) (hafasID: \(station.hafasID), globalID: \(station.globalID))")
        }
        #endif
    }

    private func loadNearbyStations() {
        guard let location = locationManager.location else { return }
        guard let accessToken = authService.accessToken else {
            hasLoadedStations = true
            return
        }

        hasLoadedStations = true
        searchText = ""

        Task {
            await graphQLService.searchStations(
                lat: location.latitude,
                lon: location.longitude,
                accessToken: accessToken
            )

            #if DEBUG
            print("📍 [StationPicker] Nahbereich → \(graphQLService.stations.count) Ergebnisse")
            for station in graphQLService.stations.prefix(3) {
                print("   • \(station.longName) (globalID: \(station.globalID))")
            }
            #endif
        }
    }

    // MARK: - Selection & Recent Stations

    private func selectAndDismiss(_ station: Station) {
        #if DEBUG
        print("✅ [StationPicker] Ausgewählt: \(station.longName) (globalID: \(station.globalID))")
        #endif
        HapticHelper.selection()
        selectedStation = station
        saveRecentStation(station)
        dismiss()
    }

    private let recentStationsKey = "recentStations"
    private let maxRecentStations = 8

    private func saveRecentStation(_ station: Station) {
        var recents = loadRecentStationsFromDefaults()
        recents.removeAll { $0.globalID == station.globalID }
        recents.insert(station, at: 0)
        if recents.count > maxRecentStations {
            recents = Array(recents.prefix(maxRecentStations))
        }
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: recentStationsKey)
        }
    }

    private func loadRecentStations() {
        recentStations = loadRecentStationsFromDefaults()
    }

    private func loadRecentStationsFromDefaults() -> [Station] {
        guard let data = UserDefaults.standard.data(forKey: recentStationsKey),
              let stations = try? JSONDecoder().decode([Station].self, from: data) else {
            return []
        }
        return stations
    }
}

// MARK: - Nearby Station Map Sheet

struct NearbyStationMapSheet: View {
    @ObservedObject var graphQLService: GraphQLService
    let userLocation: CLLocationCoordinate2D
    let accessToken: String
    let onSelect: (Station) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var geocoded: [String: CLLocationCoordinate2D] = [:]
    @State private var selected: Station?

    private static let rnvRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.4875, longitude: 8.4660),
        latitudinalMeters: 80_000,
        longitudinalMeters: 80_000
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(initialPosition: .region(
                MKCoordinateRegion(center: userLocation, latitudinalMeters: 900, longitudinalMeters: 900)
            )) {
                UserAnnotation()
                ForEach(graphQLService.stations) { station in
                    if let coord = geocoded[station.globalID] {
                        let isSelected = selected?.globalID == station.globalID
                        Annotation("", coordinate: coord, anchor: .bottom) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                                    selected = isSelected ? nil : station
                                }
                            } label: {
                                stationPin(isSelected: isSelected, name: station.longName)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .including([.publicTransport])))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .ignoresSafeArea()
            .safeAreaPadding(.bottom, selected != nil ? 140 : 0)

            if graphQLService.isLoading || (geocoded.isEmpty && !graphQLService.stations.isEmpty) {
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Haltestellen laden…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
                .padding(.bottom, 160)
            }

            if let station = selected {
                selectionCard(station: station)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: graphQLService.stations.map(\.globalID).joined()) {
            await geocodeAll()
        }
    }

    @ViewBuilder
    private func stationPin(isSelected: Bool, name: String) -> some View {
        VStack(spacing: 3) {
            if isSelected {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.primaryColor))
                    .shadow(color: AppTheme.primaryColor.opacity(0.35), radius: 4, x: 0, y: 2)
            }
            ZStack {
                Circle()
                    .fill(isSelected ? AppTheme.primaryColor : Color(.systemBackground))
                    .frame(width: isSelected ? 36 : 28, height: isSelected ? 36 : 28)
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                Image(systemName: "tram.fill")
                    .font(.system(size: isSelected ? 15 : 11, weight: .semibold))
                    .foregroundColor(isSelected ? .white : AppTheme.primaryColor)
            }
            if !isSelected {
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isSelected)
    }

    private func selectionCard(station: Station) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.primaryColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "tram.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.primaryColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.longName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text("Haltestelle auswählen")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    onSelect(station)
                } label: {
                    Text("Auswählen")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppTheme.primaryColor))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: -4)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func geocodeAll() async {
        let stations = graphQLService.stations
        await withTaskGroup(of: (String, CLLocationCoordinate2D?).self) { group in
            for station in stations {
                let id = station.globalID
                let name = station.longName
                group.addTask { (id, try? await Self.geocode(name)) }
            }
            for await (id, coord) in group {
                if let coord {
                    await MainActor.run { geocoded[id] = coord }
                }
            }
        }
    }

    private static func geocode(_ name: String) async throws -> CLLocationCoordinate2D {
        let knownCities = [
            "Mannheim", "Heidelberg", "Ludwigshafen", "Weinheim",
            "Schwetzingen", "Viernheim", "Lampertheim", "Speyer",
            "Leimen", "Sandhausen", "Walldorf", "Wiesloch",
            "Hockenheim", "Schriesheim", "Heddesheim", "Eppelheim"
        ]
        let query = knownCities.contains(where: { name.hasPrefix($0) }) ? name : "Mannheim \(name)"

        let transitReq = MKLocalSearch.Request()
        transitReq.naturalLanguageQuery = query
        transitReq.region = rnvRegion
        transitReq.resultTypes = .pointOfInterest
        transitReq.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
        if let resp = try? await MKLocalSearch(request: transitReq).start(),
           let item = resp.mapItems.first {
            return item.placemark.coordinate
        }

        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.region = rnvRegion
        let resp = try await MKLocalSearch(request: req).start()
        guard let item = resp.mapItems.first else {
            throw GeocodeError.noResultsFound
        }
        return item.placemark.coordinate
    }
}

// MARK: - Station Row Button Style

struct StationRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.secondary.opacity(0.08)
                    : Color.clear
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    StationPickerView(
        authService: AuthService(),
        graphQLService: GraphQLService(),
        locationManager: LocationManager(),
        selectedStation: .constant(nil),
        selectedDate: .constant(Date())
    )
}
