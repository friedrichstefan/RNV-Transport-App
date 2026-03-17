//
//  TripDetailView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import SwiftUI
import CoreLocation

struct TripDetailView: View {
    let trip: DetailedTrip
    let authService: AuthService

    @ObservedObject var liveActivityManager: LiveActivityManager
    @State private var isLiveActivityActive = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let formatter = DateFormattingHelper.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    tripOverviewHeader

                    if #available(iOS 16.2, *) {
                        liveActivityDetailSection
                    }

                    VStack(spacing: 16) {
                        ForEach(Array(trip.legs.enumerated()), id: \.offset) { index, leg in
                            LegDetailCard(leg: leg, isLast: index == trip.legs.count - 1)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .background(Color(colorScheme == .dark ? .black : .systemGroupedBackground))
            .navigationTitle("Verbindungsdetails")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                }

                if #available(iOS 16.2, *) {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: toggleLiveActivity) {
                            Image(systemName: isLiveActivityActive ? "bell.badge.fill" : "bell")
                                .foregroundColor(isLiveActivityActive ? .green : AppTheme.primaryColor)
                                .font(.title3)
                        }
                    }
                }
            }
        }
        .onAppear {
            if #available(iOS 16.2, *) {
                isLiveActivityActive = LiveActivityState.shared.isTripActive(trip.id.uuidString)
            }
        }
    }

    // MARK: - Trip Overview Header

    private var tripOverviewHeader: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(formatter.formatTime(trip.startTime))
                            .font(.system(size: 36, weight: .bold))

                        Image(systemName: "arrow.right")
                            .font(.title3)
                            .foregroundColor(.secondary)

                        Text(formatter.formatTime(trip.endTime))
                            .font(.system(size: 36, weight: .bold))
                    }
                    .foregroundColor(.primary)

                    Text("Fahrtdauer: \(formatter.calculateDuration(start: trip.startTime, end: trip.endTime))")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            if trip.interchanges > 0 {
                HStack {
                    Image(systemName: "arrow.triangle.swap")
                    Text("\(trip.interchanges) Umstieg\(trip.interchanges == 1 ? "" : "e")")
                }
                .font(.subheadline)
                .foregroundColor(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, y: 4)
        )
        .padding(.horizontal)
        .padding(.top, 20)
    }

    // MARK: - Live Activity Detail Section

    @available(iOS 16.2, *)
    @ViewBuilder
    private var liveActivityDetailSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live-Verfolgung")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(isLiveActivityActive ?
                         "Erhalte Updates auf dem Sperrbildschirm und in der Dynamic Island" :
                         "Aktiviere Live-Updates für diese Verbindung")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $isLiveActivityActive)
                    .labelsHidden()
                    .tint(.green)
                    .scaleEffect(1.2)
            }

            if isLiveActivityActive {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))

                        Text("Live Activity ist aktiv")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(AppTheme.primaryColor)
                            .font(.system(size: 14))

                        Text("Echtzeit-Updates werden auf dem Sperrbildschirm und in der Dynamic Island angezeigt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()
                    }
                }
                .padding(.top, 8)
            }

            if let error = liveActivityManager.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))

                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 6, y: 3)
        )
        .padding(.horizontal)
        .onChange(of: isLiveActivityActive) { newValue in
            handleToggleChange(newValue)
        }
    }

    // MARK: - Live Activity Handling

    @available(iOS 16.2, *)
    private func toggleLiveActivity() {
        isLiveActivityActive.toggle()
    }

    @available(iOS 16.2, *)
    private func handleToggleChange(_ newValue: Bool) {
        Task {
            if newValue {
                print("🟢 [DETAIL] Live Activity aktiviert für Trip: \(trip.id)")
                LiveActivityState.shared.setTripActive(trip.id.uuidString, isActive: true)
                TripDataManager.shared.saveTripData(trip)
                await liveActivityManager.startActivity(for: trip, accessToken: authService.accessToken ?? "")
            } else {
                print("🔴 [DETAIL] Live Activity deaktiviert für Trip: \(trip.id)")
                LiveActivityState.shared.setTripActive(trip.id.uuidString, isActive: false)
                TripDataManager.shared.removeTripData(for: trip.id.uuidString)
                await liveActivityManager.endActivity(tripId: trip.id.uuidString)
            }
        }
    }
}

#Preview {
    let mockTrip = DetailedTrip(
        startTime: "2026-01-18T14:30:00.000Z",
        endTime: "2026-01-18T15:15:00.000Z",
        interchanges: 1,
        legs: [
            TripLeg(
                type: .timedLeg,
                mode: "STRASSENBAHN",
                boardStopName: "Mannheim Hbf",
                alightStopName: "Heidelberg Bismarckplatz",
                departureTime: "2026-01-18T14:30:00.000Z",
                arrivalTime: "2026-01-18T14:45:00.000Z",
                estimatedDepartureTime: "2026-01-18T14:33:00.000Z",
                estimatedArrivalTime: "2026-01-18T14:48:00.000Z",
                serviceType: "STRASSENBAHN",
                serviceName: "Linie 5",
                serviceDescription: nil,
                destinationLabel: "Heidelberg Hauptbahnhof"
            ),
            TripLeg(
                type: .continuousLeg,
                mode: "WALK",
                boardStopName: nil,
                alightStopName: nil,
                departureTime: "2026-01-18T14:45:00.000Z",
                arrivalTime: "2026-01-18T14:50:00.000Z",
                estimatedDepartureTime: nil,
                estimatedArrivalTime: nil,
                serviceType: nil,
                serviceName: "Fußweg",
                serviceDescription: nil,
                destinationLabel: nil
            ),
            TripLeg(
                type: .timedLeg,
                mode: "BUS",
                boardStopName: "Heidelberg Bismarckplatz",
                alightStopName: "Heidelberg Neuenheimer Feld",
                departureTime: "2026-01-18T14:50:00.000Z",
                arrivalTime: "2026-01-18T15:15:00.000Z",
                estimatedDepartureTime: nil,
                estimatedArrivalTime: nil,
                serviceType: "BUS",
                serviceName: "Linie 33",
                serviceDescription: nil,
                destinationLabel: "Rohrbach"
            )
        ]
    )

    let mockAuthService = AuthService()
    let mockManager = LiveActivityManager()

    TripDetailView(trip: mockTrip, authService: mockAuthService, liveActivityManager: mockManager)
        .preferredColorScheme(.light)
}
