//
//  SettingsView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 14.01.26.
//

import SwiftUI
import CoreLocation

struct SettingsView: View {
    @ObservedObject var locationManager: LocationManager
    @StateObject private var liveActivityManager = LiveActivityManager()
    
    @AppStorage("autoStartLiveActivity") private var autoStartLiveActivity = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("showDelaysOnly") private var showDelaysOnly = false
    @AppStorage("defaultSearchRadius") private var defaultSearchRadius = 2.0
    @AppStorage("maxConnections") private var maxConnections = 5
    @AppStorage("enableTram") private var enableTram = true
    @AppStorage("enableBus") private var enableBus = true
    @AppStorage("enableSBahn") private var enableSBahn = true
    @AppStorage("developerMode") private var developerMode = false
    
    @State private var showingResetAlert = false
    @State private var showingCleanupSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - Standort
                Section {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Aktueller Standort")
                                .font(.subheadline)
                            if let location = locationManager.location {
                                Text("\(String(format: "%.4f", location.latitude)), \(String(format: "%.4f", location.longitude))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Nicht verfügbar")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if locationManager.isLocating {
                            ProgressView()
                        } else {
                            Button(action: {
                                locationManager.startLocationUpdates()
                            }) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                } header: {
                    Label("Standort", systemImage: "location.circle")
                }
                
                // MARK: - Live Activity
                Section {
                    Toggle("Live-Verfolgung automatisch starten", isOn: $autoStartLiveActivity)
                    Toggle("Push-Benachrichtigungen", isOn: $notificationsEnabled)
                } header: {
                    Label("Live Activity", systemImage: "bell.badge")
                } footer: {
                    Text("Automatisches Starten aktiviert Live-Verfolgung bei jeder Verbindungssuche.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Verbindungssuche
                Section {
                    Toggle("Nur verspätete Verbindungen", isOn: $showDelaysOnly)
                    
                    Stepper(value: $maxConnections, in: 3...10) {
                        HStack {
                            Text("Max. Verbindungen")
                            Spacer()
                            Text("\(maxConnections)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suchradius: \(String(format: "%.1f", defaultSearchRadius)) km")
                            .font(.subheadline)
                        Slider(value: $defaultSearchRadius, in: 0.5...5.0, step: 0.5)
                            .tint(.blue)
                    }
                } header: {
                    Label("Verbindungssuche", systemImage: "magnifyingglass")
                }
                
                // MARK: - Verkehrsmittel
                Section {
                    Toggle(isOn: $enableTram) {
                        HStack {
                            Image(systemName: "tram.fill")
                                .foregroundColor(.red)
                            Text("Straßenbahn")
                        }
                    }
                    
                    Toggle(isOn: $enableBus) {
                        HStack {
                            Image(systemName: "bus.fill")
                                .foregroundColor(.blue)
                            Text("Bus")
                        }
                    }
                    
                    Toggle(isOn: $enableSBahn) {
                        HStack {
                            Image(systemName: "train.side.front.car")
                                .foregroundColor(.green)
                            Text("S-Bahn")
                        }
                    }
                } header: {
                    Label("Verkehrsmittel", systemImage: "bus.fill")
                } footer: {
                    Text("Deaktivierte Verkehrsmittel werden bei der Suche nicht berücksichtigt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Datenverwaltung
                Section {
                    Button(role: .destructive, action: {
                        showingResetAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash.circle.fill")
                            Text("Alle Live Activities beenden")
                        }
                    }
                    
                    Button(action: {
                        Task {
                            await cleanupAllActivities()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundColor(.blue)
                            Text("Cache leeren")
                                .foregroundColor(.primary)
                        }
                    }
                } header: {
                    Label("Datenverwaltung", systemImage: "externaldrive")
                } footer: {
                    Text("Live Activities werden beendet und der Speicher wird freigegeben.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Entwickler
                Section {
                    Toggle("Entwicklermodus", isOn: $developerMode)
                    
                    if developerMode {
                        Button(action: {
                            locationManager.location = CLLocationCoordinate2D(
                                latitude: 49.483076,
                                longitude: 8.468409
                            )
                        }) {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mannheim Hbf (Test)")
                                        .foregroundColor(.primary)
                                    Text("49.4831, 8.4684")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Button(action: {
                            locationManager.location = CLLocationCoordinate2D(
                                latitude: 49.4044,
                                longitude: 8.6765
                            )
                        }) {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Heidelberg Hbf (Test)")
                                        .foregroundColor(.primary)
                                    Text("49.4044, 8.6765")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Label("Entwickler", systemImage: "hammer.fill")
                } footer: {
                    if developerMode {
                        Text("Test-Koordinaten für Entwicklung ohne GPS-Zugriff.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // MARK: - Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("2025.01")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://www.rnv-online.de")!) {
                        HStack {
                            Text("RNV Website")
                            Spacer()
                            Image(systemName: "arrow.up.forward.circle")
                                .foregroundColor(.blue)
                        }
                    }
                } header: {
                    Label("App-Info", systemImage: "info.circle")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.large)
            .alert("Alle Activities beenden?", isPresented: $showingResetAlert) {
                Button("Abbrechen", role: .cancel) { }
                Button("Beenden", role: .destructive) {
                    Task {
                        await cleanupAllActivities()
                        showingCleanupSuccess = true
                    }
                }
            } message: {
                Text("Alle aktiven Live Activities werden beendet und die Toggles zurückgesetzt.")
            }
            .alert("Erfolgreich", isPresented: $showingCleanupSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Alle Live Activities wurden beendet.")
            }
        }
    }
    
    private func cleanupAllActivities() async {
        if #available(iOS 16.2, *) {
            print("🗑️ [SETTINGS] Starte komplettes Cleanup...")
            await liveActivityManager.endAllActivitiesAndResetToggles()
            LiveActivityState.shared.deactivateAllTrips()
            print("✅ [SETTINGS] Cleanup abgeschlossen")
        }
    }
}

#Preview {
    SettingsView(locationManager: LocationManager())
}
