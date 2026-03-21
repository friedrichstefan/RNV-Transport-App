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
    @StateObject private var graphQLService = GraphQLService()
    @StateObject private var locationManager = LocationManager()

    @State private var activeTripCount = 0
    @State private var selectedTab = 0

    init() {
        // UITabBar Appearance einmalig konfigurieren (nicht bei jedem onAppear)
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        tabBarAppearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Connections Tab
            ConnectionsView(
                authService: authService,
                graphQLService: graphQLService,
                locationManager: locationManager
            )
            .tabItem {
                Label("Verbindungen", systemImage: "tram.fill")
            }
            .tag(0)

            // MARK: - Planned Trips Tab
            PlannedTripsView()
                .tabItem {
                    Label("Fahrten", systemImage: activeTripCount > 0 ? "bell.badge.fill" : "bell")
                }
                .tag(1)
                .badge(activeTripCount > 0 ? activeTripCount : 0)

            // MARK: - Settings Tab
            SettingsView(locationManager: locationManager)
                .tabItem {
                    Label("Einstellungen", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(AppTheme.primaryColor)
        .onAppear {
            #if DEBUG
            print("🔍 [xcconfig] CLIENT_ID: \(Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_ID") ?? "❌ NIL")")
            print("🔍 [xcconfig] GRAPHQL_URL: \(Bundle.main.object(forInfoDictionaryKey: "RNV_GRAPHQL_URL") ?? "❌ NIL")")
            #endif
            // Initialen Trip-Count laden
            activeTripCount = LiveActivityState.shared.getAllActiveTrips().count
        }
        .onReceive(NotificationCenter.default.publisher(for: LiveActivityState.activeTripsDidChangeNotification)) { _ in
            activeTripCount = LiveActivityState.shared.getAllActiveTrips().count
        }
        .task {
            await authService.autoAuthenticate()
            await locationManager.autoRequestLocation()
        }
        .task(id: "dailyCleanup") {
            // Einmaliger Cleanup beim Start – keine Endlosschleife nötig
            TripDataManager.shared.removeExpiredTrips()
        }
    }
}

// MARK: - App Theme

struct AppTheme {
    static let primaryColor = Color(red: 0.0, green: 0.55, blue: 0.65)
    static let secondaryColor = Color(red: 0.30, green: 0.25, blue: 0.65)
    static let accentGradient = LinearGradient(
        colors: [primaryColor, secondaryColor],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let headerBackground = LinearGradient(
        colors: [
            Color(red: 0.04, green: 0.08, blue: 0.18),
            Color(red: 0.0, green: 0.32, blue: 0.40)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cardBackground = Color(.systemBackground)
    static let subtleBackground = Color(.secondarySystemGroupedBackground)
}

#Preview {
    ContentView()
        .environmentObject(LiveActivityManager())
}
