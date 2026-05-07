//
//  StationPickerView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 09.01.26.
//

import SwiftUI
import CoreLocation

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
    @State private var isSearchingQuickStation = false
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
                    if isSearchingQuickStation {
                        // Schnellzugriff-Station wird geladen
                        VStack(spacing: 16) {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.primaryColor))
                                .scaleEffect(1.3)
                            Text("Lade Haltestelle...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else if graphQLService.isLoading && !hasLoadedStations {
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
                        searchText = ""
                        graphQLService.stations = []
                        hasLoadedStations = false
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

                // Standort-Button
                if locationManager.location != nil {
                    Button(action: loadNearbyStations) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.surfaceStrong)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "location.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppTheme.primaryColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("In der Nähe")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("Haltestellen um deinen Standort")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Bekannte Stationen für Schnellzugriff
                // Verwende Suchbegriffe statt hardcoded IDs — die API wird live abgefragt
                quickStationSection(
                    title: "Häufig gesucht",
                    icon: "star.fill",
                    stations: [
                        "Mannheim Hauptbahnhof",
                        "Heidelberg Hauptbahnhof",
                        "Paradeplatz",
                        "Ludwigshafen Hauptbahnhof",
                        "Bismarckplatz",
                    ]
                )

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

    /// Schnellzugriff: Sucht den Namen über die API und wählt das erste Ergebnis
    @ViewBuilder
    private func quickStationSection(title: String, icon: String, stations: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.3)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(stations.enumerated()), id: \.element) { index, name in
                    Button {
                        Task { await searchAndSelectQuickStation(name: name) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AppTheme.primaryColor)
                                .frame(width: 28)

                            Text(name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.3))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < stations.count - 1 {
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

    /// Sucht eine Station über die API und wählt das erste Ergebnis direkt aus
    private func searchAndSelectQuickStation(name: String) async {
        guard let accessToken = authService.accessToken else {
            #if DEBUG
            print("❌ [StationPicker] Kein Access Token für Schnellzugriff")
            #endif
            // Fallback: Suchtext setzen und manuell suchen lassen
            searchText = name
            return
        }

        isSearchingQuickStation = true

        await graphQLService.searchStationsByName(
            name: name,
            accessToken: accessToken
        )

        if let firstStation = graphQLService.stations.first {
            #if DEBUG
            print("✅ [StationPicker] Schnellzugriff '\(name)' → \(firstStation.longName) (ID: \(firstStation.globalID))")
            #endif
            isSearchingQuickStation = false
            selectAndDismiss(firstStation)
        } else {
            #if DEBUG
            print("⚠️ [StationPicker] Schnellzugriff '\(name)' ergab keine Treffer – öffne Suche")
            #endif
            isSearchingQuickStation = false
            // Fallback: Suchtext setzen, damit der User manuell suchen kann
            searchText = name
            hasLoadedStations = true
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
                    .fill(AppTheme.surfaceStrong)
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
