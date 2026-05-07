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
    @Environment(\.colorScheme) private var colorScheme

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
    @State private var showPrivacyPolicy = false

    private var cardBg: Color { AppTheme.surfaceCardAdaptive(colorScheme) }
    private var canvasBg: Color { AppTheme.canvasAdaptive(colorScheme) }
    private var dividerColor: Color { AppTheme.hairlineAdaptive(colorScheme) }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    appHeader
                    searchSection
                    transportSection
                    notificationSection
                    locationSection
                    dataSection
                    privacySection
                    if developerMode { developerSection }
                    footerSection
                    developerToggleRow
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(canvasBg.ignoresSafeArea())
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
            .sheet(isPresented: $showPrivacyPolicy) {
                PrivacyPolicyView()
            }
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        SettingsCard(title: "Datenschutz", icon: "lock.shield.fill", iconColor: .blue, cardBg: cardBg, dividerColor: dividerColor) {
            ActionRow(
                title: "Datenschutzerklärung",
                icon: "doc.text.fill",
                iconColor: .blue,
                inkColor: AppTheme.inkAdaptive(colorScheme)
            ) {
                showPrivacyPolicy = true
            }
        }
    }

    private var appHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.surfaceDark, AppTheme.surfaceDarkElevated],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)

                Image(systemName: "tram.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .shadow(color: AppTheme.surfaceDark.opacity(0.25), radius: 10, x: 0, y: 4)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("ÖPNV Mannheim")
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppTheme.inkAdaptive(colorScheme))

                HStack(spacing: 6) {
                    Text("v1.1.0")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppTheme.onDark)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.surfaceDark.opacity(0.85))
                        .clipShape(Capsule())

                    Text("Mannheim & Umgebung")
                        .font(.caption)
                        .foregroundColor(AppTheme.muted)
                }
            }

            Spacer()
        }
        .padding(20)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ÖPNV Mannheim, Version 1.1.0, Mannheim & Umgebung")
    }

    // MARK: - Search Section

    private var searchSection: some View {
        SettingsCard(title: "Verbindungssuche", icon: "magnifyingglass", iconColor: AppTheme.primaryColor, cardBg: cardBg, dividerColor: dividerColor) {
            HStack(spacing: 12) {
                IconBadge(icon: "list.number", color: AppTheme.primaryColor)
                Text("Max. Verbindungen")
                    .font(.body)
                    .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                Spacer()
                CounterControl(value: $maxConnections, range: 3...10, tint: AppTheme.primaryColor, label: "Maximale Verbindungen")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            RowDivider(color: dividerColor)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    IconBadge(icon: "scope", color: AppTheme.primaryColor)
                    Text("Suchradius")
                        .font(.body)
                        .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                    Spacer()
                    Text("\(String(format: "%.1f", defaultSearchRadius)) km")
                        .font(.body.weight(.semibold))
                        .foregroundColor(AppTheme.primaryColor)
                        .monospacedDigit()
                }
                Slider(value: $defaultSearchRadius, in: 0.5...5.0, step: 0.5)
                    .tint(AppTheme.primaryColor)
                    .padding(.leading, 44)
                    .accessibilityLabel("Suchradius")
                    .accessibilityValue("\(String(format: "%.1f", defaultSearchRadius)) Kilometer")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Transport Section

    private var transportSection: some View {
        SettingsCard(title: "Verkehrsmittel", icon: "tram.fill", iconColor: .red, cardBg: cardBg, dividerColor: dividerColor) {
            ToggleRow(title: "Straßenbahn", icon: "tram.fill", iconColor: .red, binding: $enableTram)
            RowDivider(color: dividerColor)
            ToggleRow(title: "Bus", icon: "bus.fill", iconColor: .blue, binding: $enableBus)
            RowDivider(color: dividerColor)
            ToggleRow(title: "S-Bahn", icon: "train.side.front.car", iconColor: .green, binding: $enableSBahn)
        }
    }

    // MARK: - Notification Section

    private var notificationSection: some View {
        SettingsCard(title: "Live Activity & Mitteilungen", icon: "bell.badge.fill", iconColor: .orange, cardBg: cardBg, dividerColor: dividerColor) {
            ToggleRow(
                title: "Automatisch starten",
                subtitle: "Bei jeder Verbindungssuche",
                icon: "livephoto",
                iconColor: AppTheme.primaryColor,
                binding: $autoStartLiveActivity
            )
            RowDivider(color: dividerColor)
            ToggleRow(
                title: "Push-Benachrichtigungen",
                subtitle: "Verspätungen und Änderungen",
                icon: "bell.fill",
                iconColor: .orange,
                binding: $notificationsEnabled
            )
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        SettingsCard(title: "Standort", icon: "location.fill", iconColor: AppTheme.primaryColor, cardBg: cardBg, dividerColor: dividerColor) {
            HStack(spacing: 12) {
                IconBadge(icon: "location.fill", color: AppTheme.primaryColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aktueller Standort")
                        .font(.body)
                        .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                    if let location = locationManager.location {
                        Text("\(String(format: "%.4f", location.latitude)), \(String(format: "%.4f", location.longitude))")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(AppTheme.muted)
                            .accessibilityLabel("Koordinaten: \(String(format: "%.4f", location.latitude)) nördlich, \(String(format: "%.4f", location.longitude)) östlich")
                        if developerMode {
                            Text("Teststandort aktiv")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.orange)
                        }
                    } else {
                        Text("Nicht verfügbar")
                            .font(.caption)
                            .foregroundColor(AppTheme.muted)
                    }
                }
                Spacer()
                if locationManager.isLocating {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button {
                        locationManager.startLocationUpdates()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.primaryColor)
                            .frame(width: 32, height: 32)
                            .background(AppTheme.primaryColor.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Standort aktualisieren")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        SettingsCard(title: "Datenverwaltung", icon: "externaldrive.fill", iconColor: AppTheme.muted, cardBg: cardBg, dividerColor: dividerColor) {
            ActionRow(
                title: "Cache leeren",
                icon: "arrow.clockwise",
                iconColor: AppTheme.primaryColor,
                inkColor: AppTheme.inkAdaptive(colorScheme)
            ) {
                Task { await cleanupAllActivities() }
            }
            RowDivider(color: dividerColor)
            ActionRow(
                title: "Alle Live Activities beenden",
                icon: "xmark.circle.fill",
                iconColor: AppTheme.semanticError,
                inkColor: AppTheme.semanticError
            ) {
                showingResetAlert = true
            }
        }
    }

    // MARK: - Developer Section

    private var developerSection: some View {
        SettingsCard(title: "Entwickler", icon: "hammer.fill", iconColor: .orange, cardBg: cardBg, dividerColor: dividerColor) {
            ActionRow(title: "Mannheim Hbf (Test)", icon: "mappin.circle.fill", iconColor: .orange, inkColor: AppTheme.inkAdaptive(colorScheme)) {
                locationManager.location = CLLocationCoordinate2D(latitude: 49.483076, longitude: 8.468409)
            }
            RowDivider(color: dividerColor)
            ActionRow(title: "Heidelberg Hbf (Test)", icon: "mappin.circle.fill", iconColor: .purple, inkColor: AppTheme.inkAdaptive(colorScheme)) {
                locationManager.location = CLLocationCoordinate2D(latitude: 49.4044, longitude: 8.6765)
            }
            RowDivider(color: dividerColor)
            ActionRow(title: "Debug: State ausgeben", icon: "ant.fill", iconColor: AppTheme.semanticError, inkColor: AppTheme.inkAdaptive(colorScheme)) {
                LiveActivityState.shared.debugPrintState()
            }
        }
    }

    // MARK: - Developer Toggle

    private var developerToggleRow: some View {
        HStack(spacing: 12) {
            IconBadge(icon: "hammer.fill", color: .gray)
            Text("Entwicklermodus")
                .font(.body)
                .foregroundColor(AppTheme.inkAdaptive(colorScheme))
            Spacer()
            Toggle("", isOn: $developerMode)
                .tint(.orange)
                .labelsHidden()
                .accessibilityLabel("Entwicklermodus")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 10) {
            Text("Studentenprojekt – nicht verbunden mit der rnv GmbH oder anderen Verkehrsbetrieben.")
                .font(.caption)
                .foregroundColor(AppTheme.muted)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Label("v1.1.0", systemImage: "checkmark.seal")
                Text("·")
                Label("Öffentliche Daten", systemImage: "network")
                Text("·")
                Label("Mannheim", systemImage: "mappin")
            }
            .font(.caption2)
            .foregroundColor(AppTheme.mutedSoft)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Private Methods

    private func cleanupAllActivities() async {
        UserDefaults.standard.removeObject(forKey: "recentStations")
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

// MARK: - Subcomponents

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let cardBg: Color
    let dividerColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(iconColor)
                    .accessibilityHidden(true)
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.muted)
                    .tracking(0.4)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }
}

private struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let iconColor: Color
    @Binding var binding: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(icon: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                if let sub = subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundColor(AppTheme.muted)
                }
            }
            Spacer()
            Toggle("", isOn: $binding)
                .tint(AppTheme.primaryColor)
                .labelsHidden()
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ActionRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    let inkColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(icon: icon, color: iconColor)
                Text(title)
                    .font(.body)
                    .foregroundColor(inkColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.mutedSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct IconBadge: View {
    let icon: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.14))
                .frame(width: 32, height: 32)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
        }
        .accessibilityHidden(true)
    }
}

private struct CounterControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let tint: Color
    var label: String = "Wert"

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if value > range.lowerBound { value -= 1 }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(value > range.lowerBound ? tint : AppTheme.mutedSoft)
                    .frame(width: 28, height: 28)
                    .background((value > range.lowerBound ? tint : AppTheme.mutedSoft).opacity(0.12))
                    .clipShape(Circle())
            }
            .disabled(value <= range.lowerBound)
            .accessibilityLabel("\(label) verringern")

            Text("\(value)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 20, alignment: .center)
                .accessibilityHidden(true)

            Button {
                if value < range.upperBound { value += 1 }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(value < range.upperBound ? tint : AppTheme.mutedSoft)
                    .frame(width: 28, height: 28)
                    .background((value < range.upperBound ? tint : AppTheme.mutedSoft).opacity(0.12))
                    .clipShape(Circle())
            }
            .disabled(value >= range.upperBound)
            .accessibilityLabel("\(label) erhöhen")
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(value)")
    }
}

private struct RowDivider: View {
    let color: Color
    var body: some View {
        color
            .frame(height: 0.5)
            .padding(.leading, 60)
    }
}

#Preview {
    SettingsView(locationManager: LocationManager())
        .environmentObject(LiveActivityManager())
}
