//
//  TripDetailView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import SwiftUI
import CoreLocation

// MARK: - Enhanced Trip Detail View with Live Activity Toggle

struct TripDetailView: View {
    let trip: DetailedTrip
    let authService: AuthService
    
    // Live Activity Management
    @StateObject private var liveActivityManager = LiveActivityManager()
    @State private var isLiveActivityActive = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Trip Overview Header
                    tripOverviewHeader
                    
                    // Live Activity Section
                    if #available(iOS 16.2, *) {
                        liveActivityDetailSection
                    }
                    
                    // Leg Details
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
                
                // Live Activity Toolbar Button
                ToolbarItem(placement: .navigationBarLeading) {
                    if #available(iOS 16.2, *) {
                        Button(action: toggleLiveActivity) {
                            Image(systemName: isLiveActivityActive ? "bell.badge.fill" : "bell")
                                .foregroundColor(isLiveActivityActive ? .green : .blue)
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
                        Text(formatTime(trip.startTime))
                            .font(.system(size: 36, weight: .bold))
                        
                        Image(systemName: "arrow.right")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Text(formatTime(trip.endTime))
                            .font(.system(size: 36, weight: .bold))
                    }
                    .foregroundColor(.primary)
                    
                    Text("Fahrtdauer: \(calculateDuration(start: trip.startTime, end: trip.endTime))")
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
                            .foregroundColor(.blue)
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
            
            // Error Display
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
        .onChange(of: isLiveActivityActive) { oldValue, newValue in
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
                await liveActivityManager.startActivity(for: trip, accessToken: authService.accessToken ?? "")
            } else {
                print("🔴 [DETAIL] Live Activity deaktiviert für Trip: \(trip.id)")
                LiveActivityState.shared.setTripActive(trip.id.uuidString, isActive: false)
                await liveActivityManager.endActivity(tripId: trip.id.uuidString)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: isoString) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            timeFormatter.timeZone = .current
            return timeFormatter.string(from: date)
        }
        return isoString
    }
    
    private func calculateDuration(start: String, end: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let startDate = formatter.date(from: start),
              let endDate = formatter.date(from: end) else { return "?" }
        
        let duration = endDate.timeIntervalSince(startDate)
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}

// MARK: - Preview

#Preview {
    // Mock Data für Preview
    let mockTrip = DetailedTrip(
        startTime: "2026-01-18T14:30:00.000Z",
        endTime: "2026-01-18T15:15:00.000Z",
        interchanges: 1,
        legs: [
            TripLeg(
                type: "TimedLeg",
                mode: "STRASSENBAHN",
                boardStopName: "STRASSENBAHN",
                alightStopName: "RNV 5",
                departureTime: "Straßenbahn Linie 5 Richtung Heidelberg",
                arrivalTime: "Heidelberg Hauptbahnhof",
                estimatedDepartureTime: "Mannheim Hauptbahnhof",
                estimatedArrivalTime: "Heidelberg Bismarckplatz",
                serviceType: "2026-01-18T14:30:00.000Z",
                serviceName: "2026-01-18T14:45:00.000Z",
                serviceDescription: "2026-01-18T14:33:00.000Z", // 3 Min Verspätung
                destinationLabel: "2026-01-18T14:48:00.000Z"
            ),
            TripLeg(
                type: "WALK",
                mode: "WALK",
                boardStopName: nil,
                alightStopName: "Fußweg",
                departureTime: "Fußweg zwischen Haltestellen",
                arrivalTime: nil,
                estimatedDepartureTime: nil,
                estimatedArrivalTime: nil,
                serviceType: "2026-01-18T14:45:00.000Z",
                serviceName: "2026-01-18T14:50:00.000Z",
                serviceDescription: nil,
                destinationLabel: nil
            ),
            TripLeg(
                type: "TimedLeg",
                mode: "BUS",
                boardStopName: "BUS",
                alightStopName: "RNV 33",
                departureTime: "Bus Linie 33 Richtung Rohrbach",
                arrivalTime: "Heidelberg Rohrbach",
                estimatedDepartureTime: "Heidelberg Bismarckplatz",
                estimatedArrivalTime: "Heidelberg Neuenheimer Feld",
                serviceType: "2026-01-18T14:50:00.000Z",
                serviceName: "2026-01-18T15:15:00.000Z",
                serviceDescription: nil,
                destinationLabel: nil
            )
        ]
    )
    
    let mockAuthService = AuthService()
    
    TripDetailView(trip: mockTrip, authService: mockAuthService)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    // Mock Data für Dark Mode Preview
    let mockTrip = DetailedTrip(
        startTime: "2026-01-18T14:30:00.000Z",
        endTime: "2026-01-18T15:15:00.000Z",
        interchanges: 2,
        legs: [
            TripLeg(
                type: "TimedLeg",
                mode: "S_BAHN",
                boardStopName: "S_BAHN",
                alightStopName: "S1",
                departureTime: "S-Bahn S1 Richtung Heidelberg",
                arrivalTime: "Heidelberg Hauptbahnhof",
                estimatedDepartureTime: "Mannheim Hauptbahnhof",
                estimatedArrivalTime: "Weinheim",
                serviceType: "2026-01-18T14:30:00.000Z",
                serviceName: "2026-01-18T14:40:00.000Z",
                serviceDescription: "2026-01-18T14:37:00.000Z", // 7 Min Verspätung
                destinationLabel: "2026-01-18T14:47:00.000Z"
            ),
            TripLeg(
                type: "TimedLeg",
                mode: "STRASSENBAHN",
                boardStopName: "STRASSENBAHN",
                alightStopName: "RNV 3",
                departureTime: "Straßenbahn Linie 3 Richtung Universität",
                arrivalTime: "Heidelberg Universität",
                estimatedDepartureTime: "Weinheim Hauptbahnhof",
                estimatedArrivalTime: "Heidelberg Alte Brücke",
                serviceType: "2026-01-18T14:45:00.000Z",
                serviceName: "2026-01-18T15:15:00.000Z",
                serviceDescription: nil,
                destinationLabel: nil
            )
        ]
    )
    
    let mockAuthService = AuthService()
    
    TripDetailView(trip: mockTrip, authService: mockAuthService)
        .preferredColorScheme(.dark)
}

#Preview("Direct Trip") {
    // Mock Data für direkte Verbindung ohne Umstieg
    let mockTrip = DetailedTrip(
        startTime: "2026-01-18T16:00:00.000Z",
        endTime: "2026-01-18T16:25:00.000Z",
        interchanges: 0,
        legs: [
            TripLeg(
                type: "TimedLeg",
                mode: "STRASSENBAHN",
                boardStopName: "STRASSENBAHN",
                alightStopName: "RNV 1",
                departureTime: "Straßenbahn Linie 1 Richtung Schönau",
                arrivalTime: "Mannheim Schönau",
                estimatedDepartureTime: "Mannheim Paradeplatz",
                estimatedArrivalTime: "Mannheim Neckarau",
                serviceType: "2026-01-18T16:00:00.000Z",
                serviceName: "2026-01-18T16:25:00.000Z",
                serviceDescription: nil,
                destinationLabel: nil
            )
        ]
    )
    
    let mockAuthService = AuthService()
    
    TripDetailView(trip: mockTrip, authService: mockAuthService)
        .preferredColorScheme(.light)
}
