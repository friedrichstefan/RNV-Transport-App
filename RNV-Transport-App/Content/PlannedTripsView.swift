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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.canvasAdaptive(colorScheme)
                    .ignoresSafeArea()

                if activeTrips.isEmpty {
                    emptyStateView
                } else {
                    activeTripsList
                }
            }
            .navigationTitle("Geplante Fahrten")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
        .onAppear {
            refreshActiveTrips()
            TripDataManager.shared.removeExpiredTrips()
        }
        .onReceive(NotificationCenter.default.publisher(for: LiveActivityState.activeTripsDidChangeNotification)) { _ in
            refreshActiveTrips()
        }
    }

    // MARK: - Empty State

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
    }

    // MARK: - Active Trips List

    private var activeTripsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(activeTrips, id: \.self) { tripId in
                    PlannedTripCard(
                        tripId: tripId,
                        onRemove: {
                            removeTrip(tripId)
                        }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Helper Functions

    private func refreshActiveTrips() {
        activeTrips = LiveActivityState.shared.getAllActiveTrips()
        #if DEBUG
        print("🔄 [REFRESH] \(activeTrips.count) aktive Trips gefunden")
        #endif
    }

    private func removeTrip(_ tripId: String) {
        Task {
            await liveActivityManager.endActivity(tripId: tripId)
            activeTrips.removeAll { $0 == tripId }
        }
    }

    private func endAllTrips() {
        Task {
            await liveActivityManager.endAllActivitiesAndResetToggles()
            activeTrips.removeAll()
        }
    }
}

#Preview {
    PlannedTripsView()
        .environmentObject(LiveActivityManager())
}
