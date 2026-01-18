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
    @StateObject private var graphQLService = SecureGraphQLService() // ✅ Sicherer Service
    @StateObject private var locationManager = LocationManager()
    
    @State private var activeTripCount = 0
    
    var body: some View {
        TabView {
            // MARK: - Verbindungen Tab
            ConnectionsView(
                authService: authService,
                graphQLService: graphQLService,
                locationManager: locationManager
            )
            .tabItem {
                Label("Verbindungen", systemImage: "tram.fill")
            }
            
            // MARK: - Geplante Fahrten Tab
            PlannedTripsView()
                .tabItem {
                    Label("Geplante Fahrten", systemImage: activeTripCount > 0 ? "bell.badge.fill" : "bell.badge")
                }
            
            // MARK: - Einstellungen Tab
            SettingsView(locationManager: locationManager)
                .tabItem {
                    Label("Einstellungen", systemImage: "gearshape.fill")
                }
        }
        .onAppear {
            // ✅ xcconfig Validierung
            print("🔍 [xcconfig] CLIENT_ID: \(Bundle.main.object(forInfoDictionaryKey: "RNV_CLIENT_ID") ?? "❌ NIL")")
            print("🔍 [xcconfig] GRAPHQL_URL: \(Bundle.main.object(forInfoDictionaryKey: "RNV_GRAPHQL_URL") ?? "❌ NIL")")
            
            updateActiveTripCount()
            
            // Certificate Pinning Setup (nur beim ersten Start)
            #if DEBUG
            graphQLService.setupCertificatePinning()
            #endif
            
            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                updateActiveTripCount()
            }
        }
        .task {
            await authService.autoAuthenticate()
            await locationManager.autoRequestLocation()
        }
    }
    
    private func updateActiveTripCount() {
        activeTripCount = LiveActivityState.shared.getAllActiveTrips().count
    }
    
    private func validateConfiguration() {
        #if DEBUG
        print("🔍 [SECURITY] Starte Konfigurationsvalidierung...")
        
        let requiredKeys = [
            "RNV_CLIENT_ID",
            "RNV_CLIENT_SECRET",
            "RNV_TENANT_ID",
            "RNV_RESOURCE",
            "RNV_GRAPHQL_URL"
        ]
        
        var missingKeys: [String] = []
        
        for key in requiredKeys {
            if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
               !value.isEmpty {
                print("✅ [CONFIG] \(key): Konfiguriert")
            } else {
                print("❌ [CONFIG] \(key): FEHLT!")
                missingKeys.append(key)
            }
        }
        
        if !missingKeys.isEmpty {
            let errorMessage = """
            🚨 CONFIGURATION FEHLER:
            
            Folgende Keys sind nicht konfiguriert:
            \(missingKeys.joined(separator: "\n"))
            
            Lösung:
            1. Erstelle Config.xcconfig aus Template.xcconfig
            2. Fülle alle RNV Credentials aus
            3. Baue die App neu
            """
            
            print(errorMessage)
            assertionFailure("Konfiguration unvollständig!")
        } else {
            print("✅ [SECURITY] Alle Konfigurationen sind vollständig")
        }
        #endif
    }
    
}

#Preview {
    ContentView()
}
