//
//  ContentView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 09.01.26.
//

import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var authService = AuthService()
    @StateObject private var graphQLService = SecureGraphQLService()
    @StateObject private var locationManager = LocationManager()

    @State private var activeTripCount = 0
    @State private var refreshTask: Task<Void, Never>?
    @State private var cleanupTask: Task<Void, Never>?

    var body: some View {
        TabView {
            // MARK: - Connections Tab
            ConnectionsView(
                authService: authService,
                graphQLService: graphQLService,
                locationManager: locationManager
            )
            .tabItem {
                Label("Verbindungen", systemImage: "tram.fill")
            }

            // MARK: - Planned Trips Tab
            PlannedTripsView()
                .tabItem {
                    Label("Geplante Fahrten", systemImage: activeTripCount > 0 ? "bell.badge.fill" : "bell.badge")
                }

            // MARK: - Settings Tab
            SettingsView(locationManager: locationManager)
                .tabItem {
                    Label("Einstellungen", systemImage: "gearshape.fill")
                }
        }
        .onAppear {
            #if DEBUG
            print("🔍 [xcconfig] CLIENT_ID: \(Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_ID") ?? "❌ NIL")")
            print("🔍 [xcconfig] GRAPHQL_URL: \(Bundle.main.object(forInfoDictionaryKey: "RNV_GRAPHQL_URL") ?? "❌ NIL")")
            #endif

            // Certificate Pinning muss auch im Release-Build eingerichtet werden
            graphQLService.setupCertificatePinning()

            startPeriodicRefresh()
            startDailyCleanup()
        }
        .onDisappear {
            refreshTask?.cancel()
            cleanupTask?.cancel()
        }
        .task {
            await authService.autoAuthenticate()
            await locationManager.autoRequestLocation()
        }
    }

    // MARK: - Periodic Refresh using structured concurrency

    private func startPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                activeTripCount = LiveActivityState.shared.getAllActiveTrips().count
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func startDailyCleanup() {
        cleanupTask?.cancel()
        cleanupTask = Task {
            // Sofort beim App-Start abgelaufene Trips entfernen
            TripDataManager.shared.removeExpiredTrips()
            print("✅ [CLEANUP] Initiales Cleanup beim App-Start abgeschlossen")

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(86400))
                guard !Task.isCancelled else { break }
                TripDataManager.shared.removeExpiredTrips()
                print("✅ [CLEANUP] Tägliches Cleanup abgeschlossen")
            }
        }
    }
}

#Preview {
    ContentView()
}
