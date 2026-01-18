//
//  StationPickerView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 09.01.26.
//

import Combine
import SwiftUI
import CoreLocation

struct StationPickerView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var graphQLService: GraphQLService
    @ObservedObject var locationManager: LocationManager
    @Binding var selectedStation: Station?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasLoadedStations = false
    @State private var searchText = ""
    @State private var searchDebounceTimer: Timer?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    searchField
                        .padding()
                    
                    if searchText.isEmpty && !hasLoadedStations {
                        nearbyButton
                            .padding(.horizontal)
                            .padding(.bottom, 16)
                    }
                    
                    if graphQLService.isLoading {
                        loadingView
                    } else if !graphQLService.stations.isEmpty {
                        stationList
                    } else if hasLoadedStations {
                        emptyStateView
                    } else {
                        Spacer()
                    }
                }
            }
            .navigationTitle("Haltestelle wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            handleSearchTextChange(newValue)
        }
    }
    
    // MARK: - Search Field
    
    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16, weight: .medium))
            
            TextField("Haltestelle suchen", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .autocorrectionDisabled()
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    graphQLService.stations = []
                    hasLoadedStations = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Nearby Button
    
    private var nearbyButton: some View {
        Button(action: loadNearbyStations) {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Haltestellen in der Nähe")
                    .font(.headline)
            }
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
        .disabled(locationManager.location == nil)
        .opacity(locationManager.location == nil ? 0.5 : 1.0)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)
            Text("Suche Haltestellen...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Station List
    
    private var stationList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(graphQLService.stations) { station in
                    StationRow(station: station) {
                        selectedStation = station
                        dismiss()
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Keine Haltestellen gefunden")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Versuche einen anderen Suchbegriff")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
        }
    }
    
    // MARK: - Search Handling
    
    private func handleSearchTextChange(_ newValue: String) {
        searchDebounceTimer?.invalidate()
        
        guard !newValue.isEmpty else {
            graphQLService.stations = []
            hasLoadedStations = false
            return
        }
        
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            Task {
                await searchStations(query: newValue)
            }
        }
    }
    
    private func searchStations(query: String) async {
        guard let accessToken = authService.accessToken else { return }
        
        hasLoadedStations = true
        
        await graphQLService.searchStationsByName(
            name: query,
            accessToken: accessToken
        )
    }
    
    private func loadNearbyStations() {
        guard let location = locationManager.location,
              let accessToken = authService.accessToken else {
            return
        }
        
        hasLoadedStations = true
        
        Task {
            await graphQLService.searchStations(
                lat: location.latitude,
                lon: location.longitude,
                accessToken: accessToken
            )
        }
    }
}

// MARK: - Station Row

struct StationRow: View {
    let station: Station
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "tram.fill.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.longName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text("ID: \(station.hafasID)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

#Preview {
    StationPickerView(
        authService: AuthService(),
        graphQLService: GraphQLService(),
        locationManager: LocationManager(),
        selectedStation: .constant(nil)
    )
}
