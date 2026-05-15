//
//  PlannedTripsView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import SwiftUI

struct PlannedTripsView: View {
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @State private var activeTrips: [String] = []
    @State private var archivedTrips: [ArchivedTripData] = []
    @State private var showArchive = false

    @Environment(\.colorScheme) private var colorScheme

    private let formatter = DateFormattingHelper.shared

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.canvasAdaptive(colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Segmented Picker (immer anzeigen sobald Archiv Daten hat oder aktiv ist)
                    if !archivedTrips.isEmpty || showArchive {
                        Picker("Ansicht", selection: $showArchive) {
                            Text("Aktiv").tag(false)
                            Text("Archiv").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }

                    if showArchive {
                        if archivedTrips.isEmpty {
                            archiveEmptyStateView
                        } else {
                            archivedTripsList
                        }
                    } else {
                        if activeTrips.isEmpty {
                            emptyStateView
                        } else {
                            activeTripsList
                        }
                    }
                }
            }
            .navigationTitle("Geplante Fahrten")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if showArchive {
                    if !archivedTrips.isEmpty {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: clearArchive) {
                                Text("Archiv leeren")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: refreshActiveTrips) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(AppTheme.primaryColor)
                        }
                    }

                    if !activeTrips.isEmpty {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: endAllTrips) {
                                Text("Alle beenden")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            refreshActiveTrips()
            refreshArchivedTrips()
            TripDataManager.shared.removeExpiredTrips()
        }
        .onReceive(NotificationCenter.default.publisher(for: LiveActivityState.activeTripsDidChangeNotification)) { _ in
            refreshActiveTrips()
            refreshArchivedTrips()
        }
        .onReceive(NotificationCenter.default.publisher(for: TripDataManager.archivedTripsDidChangeNotification)) { _ in
            refreshArchivedTrips()
        }
    }

    // MARK: - Active Trips

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                RadialGradient(
                    colors: [AppTheme.gradientLavender.opacity(0.5), .clear],
                    center: .center, startRadius: 0, endRadius: 100
                )
                .frame(width: 200, height: 200)
                Image(systemName: "bell.slash")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(AppTheme.muted)
            }

            VStack(spacing: 8) {
                Text("Keine aktiven Fahrten")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("Live Activities werden hier angezeigt,\nsobald du eine Verbindung verfolgst")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var activeTripsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(activeTrips, id: \.self) { tripId in
                    PlannedTripCard(
                        tripId: tripId,
                        onRemove: { refreshActiveTrips() }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Archive

    private var archiveEmptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                RadialGradient(
                    colors: [AppTheme.gradientMint.opacity(0.4), .clear],
                    center: .center, startRadius: 0, endRadius: 100
                )
                .frame(width: 200, height: 200)
                Image(systemName: "archivebox")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(AppTheme.muted)
            }

            VStack(spacing: 8) {
                Text("Archiv leer")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("Abgeschlossene Fahrten erscheinen\nhier nach Beendigung")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var archivedTripsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(archivedTrips) { trip in
                    ArchivedTripRow(trip: trip)
                }
            }
            .padding()
        }
    }

    // MARK: - Helper Actions

    private func refreshActiveTrips() {
        activeTrips = LiveActivityState.shared.getAllActiveTrips()
    }

    private func refreshArchivedTrips() {
        archivedTrips = TripDataManager.shared.getArchivedTrips()
    }

    private func clearArchive() {
        TripDataManager.shared.clearArchivedTrips()
        archivedTrips = []
    }

    private func endAllTrips() {
        Task {
            for tripId in activeTrips {
                TripDataManager.shared.archiveAndRemoveTripData(for: tripId)
            }
            await liveActivityManager.endAllActivitiesAndResetToggles()
            activeTrips.removeAll()
        }
    }
}

// MARK: - Archived Trip Row

private struct ArchivedTripRow: View {
    let trip: ArchivedTripData

    @Environment(\.colorScheme) private var colorScheme
    private let formatter = DateFormattingHelper.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Date label
            HStack {
                Text(formatter.formatDate(trip.startTime))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedSoft)
                    .textCase(.uppercase)
                    .tracking(0.3)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.green.opacity(0.6))
            }

            // Times + route
            HStack(spacing: 8) {
                Text(formatter.formatTime(trip.startTime))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.inkAdaptive(colorScheme))

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.mutedSoft)

                Text(formatter.formatTime(trip.endTime))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.inkAdaptive(colorScheme))

                Spacer()

                // Duration pill
                Text(formatter.calculateDuration(start: trip.startTime, end: trip.endTime))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.surfaceStrongAdaptive(colorScheme)))
            }

            // Stations
            HStack(spacing: 5) {
                Text(trip.startStation)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.bodyTextAdaptive(colorScheme))
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.mutedSoft)
                Text(trip.endStation)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.bodyTextAdaptive(colorScheme))
                    .lineLimit(1)
            }

            // Line badges
            let timedLegs = trip.legs.filter { $0.legType != "continuousLeg" }
            if !timedLegs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(timedLegs.enumerated()), id: \.offset) { _, leg in
                        if let st = leg.serviceType, let sn = leg.serviceName {
                            archivedLineBadge(serviceType: st, serviceName: sn)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                .shadow(color: AppTheme.shadowColor(isPast: true), radius: 4, y: 2)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
        )
    }

    private func archivedLineBadge(serviceType: String, serviceName: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: TransportIconHelper.getTransportIcon(for: serviceType, serviceName: serviceName))
                .font(.system(size: 7, weight: .bold))
            Text(TransportIconHelper.getShortLineName(from: serviceName))
                .font(.system(size: 9, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(TransportIconHelper.getLineColor(for: serviceType, serviceName: serviceName).opacity(0.7))
        )
    }
}

#Preview {
    PlannedTripsView()
        .environmentObject(LiveActivityManager())
}
