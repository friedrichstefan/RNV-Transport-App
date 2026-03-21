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
    @EnvironmentObject var liveActivityManager: LiveActivityManager

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
                // MARK: - About Section (NEU – ganz oben)
                Section {
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(AppTheme.accentGradient)
                                    .frame(width: 64, height: 64)

                                Image(systemName: "tram.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white)
                                    .symbolRenderingMode(.hierarchical)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("ÖPNV Mannheim")
                                    .font(.title3)
                                    .fontWeight(.bold)

                                Text("Mannheim & Umgebung")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        Text("Dies ist ein unabhängiges Studentenprojekt und steht in keiner Verbindung zur rnv GmbH oder anderen Verkehrsbetrieben. Die App nutzt ausschließlich öffentlich zugängliche Fahrplandaten für den Raum Mannheim und Umgebung.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Location Section
                Section {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(AppTheme.primaryColor)
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
                                    .foregroundStyle(AppTheme.primaryColor)
                            }
                        }
                    }
                } header: {
                    Label("Standort", systemImage: "location.circle")
                }

                // MARK: - Live Activity Section
                Section {
                    Toggle("Live-Verfolgung automatisch starten", isOn: $autoStartLiveActivity)
                        .tint(AppTheme.primaryColor)
                    Toggle("Push-Benachrichtigungen", isOn: $notificationsEnabled)
                        .tint(AppTheme.primaryColor)
                } header: {
                    Label("Live Activity", systemImage: "bell.badge")
                } footer: {
                    Text("Automatisches Starten aktiviert Live-Verfolgung bei jeder Verbindungssuche.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Search Section
                Section {
                    Toggle("Nur verspätete Verbindungen", isOn: $showDelaysOnly)
                        .tint(AppTheme.primaryColor)

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
                            .tint(AppTheme.primaryColor)
                    }
                } header: {
                    Label("Verbindungssuche", systemImage: "magnifyingglass")
                }

                // MARK: - Transport Modes
                Section {
                    Toggle(isOn: $enableTram) {
                        HStack {
                            Image(systemName: "tram.fill")
                                .foregroundColor(.red)
                            Text("Straßenbahn")
                        }
                    }
                    .tint(AppTheme.primaryColor)

                    Toggle(isOn: $enableBus) {
                        HStack {
                            Image(systemName: "bus.fill")
                                .foregroundColor(.blue)
                            Text("Bus")
                        }
                    }
                    .tint(AppTheme.primaryColor)

                    Toggle(isOn: $enableSBahn) {
                        HStack {
                            Image(systemName: "train.side.front.car")
                                .foregroundColor(.green)
                            Text("S-Bahn")
                        }
                    }
                    .tint(AppTheme.primaryColor)
                } header: {
                    Label("Verkehrsmittel", systemImage: "bus.fill")
                } footer: {
                    Text("Deaktivierte Verkehrsmittel werden bei der Suche nicht berücksichtigt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Data Management
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
                                .foregroundStyle(AppTheme.primaryColor)
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

                // MARK: - Developer Section
                Section {
                    Toggle("Entwicklermodus", isOn: $developerMode)
                        .tint(AppTheme.primaryColor)

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

                        Button(action: {
                            LiveActivityState.shared.debugPrintState()
                        }) {
                            HStack {
                                Image(systemName: "ant.fill")
                                    .foregroundColor(.red)
                                Text("Debug: State ausdrucken")
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                } header: {
                    Label("Entwickler", systemImage: "hammer.fill")
                } footer: {
                    if developerMode {
                        Text("Test-Koordinaten und Debug-Tools für Entwicklung.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - App Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.1.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("2025.01.20")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Datenquelle")
                        Spacer()
                        Text("Öffentliche ÖPNV-Daten")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Region")
                        Spacer()
                        Text("Mannheim & Umgebung")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("App-Info", systemImage: "info.circle")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Studentenprojekt – Keine offizielle App eines Verkehrsunternehmens.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Alle Fahrplandaten stammen aus öffentlich zugänglichen Schnittstellen. Für die Richtigkeit der Daten wird keine Gewähr übernommen.")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
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
            #if DEBUG
            print("🗑️ [SETTINGS] Starte komplettes Cleanup...")
            #endif
            await liveActivityManager.endAllActivitiesAndResetToggles()
            LiveActivityState.shared.deactivateAllTrips()
            #if DEBUG
            print("✅ [SETTINGS] Cleanup abgeschlossen")
            #endif
        }
    }
}

#Preview {
    SettingsView(locationManager: LocationManager())
        .environmentObject(LiveActivityManager())
}
