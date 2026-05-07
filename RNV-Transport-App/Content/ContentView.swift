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
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(Color(hex: "#f5f5f5"))
        tabBarAppearance.shadowColor = UIColor(Color(hex: "#e7e5e4"))
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

            // MARK: - Departure Board Tab
            DepartureBoardView(
                authService: authService,
                locationManager: locationManager
            )
            .tabItem {
                Label("Abfahrten", systemImage: "clock.fill")
            }
            .tag(1)

            // MARK: - Planned Trips Tab
            PlannedTripsView()
                .tabItem {
                    Label("Fahrten", systemImage: activeTripCount > 0 ? "bell.badge.fill" : "bell")
                }
                .tag(2)
                .badge(activeTripCount > 0 ? activeTripCount : 0)

            // MARK: - Settings Tab
            SettingsView(locationManager: locationManager)
                .tabItem {
                    Label("Einstellungen", systemImage: "gearshape.fill")
                }
                .tag(3)
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
    // Canvas & Surfaces
    static let canvas         = Color(hex: "#f5f5f5")
    static let canvasSoft     = Color(hex: "#fafafa")
    static let surfaceCard    = Color.white
    static let surfaceStrong  = Color(hex: "#f0efed")
    static let hairline       = Color(hex: "#e7e5e4")
    static let hairlineStrong = Color(hex: "#d6d3d1")
    // Text
    static let ink       = Color(hex: "#0c0a09")
    static let bodyText  = Color(hex: "#4e4e4e")
    static let muted     = Color(hex: "#777169")
    static let mutedSoft = Color(hex: "#a8a29e")
    // Actions
    static let primary       = Color(hex: "#292524")
    static let primaryActive = Color(hex: "#0c0a09")
    static let primaryColor  = Color(hex: "#292524")
    // Dark hero surfaces
    static let surfaceDark         = Color(hex: "#0c0a09")
    static let surfaceDarkElevated = Color(hex: "#1c1917")
    static let onDark              = Color.white
    static let onDarkSoft          = Color(hex: "#a8a29e")
    // Atmospheric gradient orbs (decoration only)
    static let gradientMint     = Color(hex: "#a7e5d3")
    static let gradientPeach    = Color(hex: "#f4c5a8")
    static let gradientLavender = Color(hex: "#c8b8e0")
    static let gradientSky      = Color(hex: "#a8c8e8")
    static let gradientRose     = Color(hex: "#e8b8c4")
    // Semantic
    static let semanticError   = Color(hex: "#dc2626")
    static let semanticSuccess = Color(hex: "#16a34a")
    // Legacy aliases — existing callers update automatically
    static let accentGradient   = LinearGradient(colors: [primary, primary], startPoint: .leading, endPoint: .trailing)
    static let headerBackground = LinearGradient(colors: [surfaceDark, surfaceDarkElevated], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cardBackground   = surfaceCard
    static let subtleBackground = surfaceStrong
    static let secondaryColor   = Color(hex: "#292524")
    // Shadow
    static func shadowColor(isPast: Bool = false) -> Color {
        Color.black.opacity(isPast ? 0.03 : 0.05)
    }
    // Typography
    static func displayFont(size: CGFloat) -> Font { .system(size: size, weight: .light, design: .serif) }
    static let buttonFont = Font.system(size: 15, weight: .medium)
    static func monoFont(size: CGFloat, weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    // Dark-mode adaptive surfaces
    static func canvasAdaptive(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: "#1c1917") : canvas }
    static func surfaceCardAdaptive(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: "#292524") : surfaceCard }
    static func surfaceStrongAdaptive(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: "#3c3836") : surfaceStrong }
    static func hairlineAdaptive(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: "#44403c") : hairline }
    static func inkAdaptive(_ s: ColorScheme) -> Color { s == .dark ? onDark : ink }
}

// MARK: - Color(hex:) initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

#Preview {
    ContentView()
        .environmentObject(LiveActivityManager())
}
