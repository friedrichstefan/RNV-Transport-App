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
        .tint(AppTheme.primaryColor)
        .onAppear {
            #if DEBUG
            print("🔍 [xcconfig] CLIENT_ID: \(Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_ID") ?? "❌ NIL")")
            print("🔍 [xcconfig] GRAPHQL_URL: \(Bundle.main.object(forInfoDictionaryKey: "RNV_GRAPHQL_URL") ?? "❌ NIL")")
            #endif

            graphQLService.setupCertificatePinning()

            startPeriodicRefresh()
            startDailyCleanup()

            // Tab Bar Appearance
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithDefaultBackground()
            UITabBar.appearance().standardAppearance = tabBarAppearance
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
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

// MARK: - App Theme

struct AppTheme {
    static let primaryColor = Color(red: 0.0, green: 0.55, blue: 0.65) // Teal
    static let secondaryColor = Color(red: 0.30, green: 0.25, blue: 0.65) // Indigo
    static let accentGradient = LinearGradient(
        colors: [primaryColor, secondaryColor],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let headerBackground = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.12, blue: 0.22),
            Color(red: 0.0, green: 0.30, blue: 0.40)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cardBackground = Color(.systemBackground)
    static let subtleBackground = Color(.secondarySystemGroupedBackground)
}

#Preview {
    ContentView()
}
