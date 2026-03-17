//
//  PlannedTripsView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import SwiftUI

struct PlannedTripsView: View {
    @StateObject private var liveActivityManager = LiveActivityManager()
    @State private var activeTrips: [String] = []
    @State private var refreshTask: Task<Void, Never>?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .systemGroupedBackground)
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
            startRefreshTask()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.primaryColor.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "bell.slash")
                    .font(.system(size: 50))
                    .foregroundStyle(AppTheme.primaryColor.opacity(0.5))
            }

            Text("Keine aktiven Fahrten")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text("Live Activities werden hier angezeigt,\nsobald du eine Verbindung verfolgst")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
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
        print("🔄 [REFRESH] \(activeTrips.count) aktive Trips gefunden")
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

    private func startRefreshTask() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                refreshActiveTrips()
            }
        }
    }
}

#Preview {
    PlannedTripsView()
}
