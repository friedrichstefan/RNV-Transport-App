//
//  TripDetailView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import SwiftUI
import CoreLocation
import MapKit

struct TripDetailView: View {
    let trip: DetailedTrip
    let authService: AuthService

    @ObservedObject var liveActivityManager: LiveActivityManager
    @State private var isLiveActivityActive = false
    @State private var didAppear = false
    @State private var showShareSheet = false
    @State private var showFullMap = false

    @StateObject private var mapVM = TransitMapViewModel()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let formatter = DateFormattingHelper.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    tripOverviewHeader

                    if #available(iOS 16.2, *) {
                        liveActivityRow
                    }

                    TripJourneyView(legs: trip.legs)
                        .padding(.horizontal)
                        .padding(.bottom, 8)

                    mapSection
                        .padding(.bottom, 30)
                }
            }
            .background(AppTheme.canvasAdaptive(colorScheme).ignoresSafeArea())
            .navigationTitle("Verbindungsdetails")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(AppTheme.primaryColor)
                        }
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppTheme.mutedSoft)
                                .font(.title3)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [generateShareText()])
        }
        .task {
            await mapVM.loadStops(legs: trip.legs)
        }
        .onAppear {
            if #available(iOS 16.2, *) {
                isLiveActivityActive = LiveActivityState.shared.isTripActive(trip.id.uuidString)
            }
            didAppear = true
        }
    }

    // MARK: - Trip Overview Header

    private var tripOverviewHeader: some View {
        let depDelay = getFirstLegDelay()
        let arrDelay = getLastLegDelay()
        let maxDelay = max(depDelay ?? 0, arrDelay ?? 0)
        let origin = trip.legs.first(where: { $0.isTimedLeg })?.boardStopName
        let destination = trip.legs.last(where: { $0.isTimedLeg })?.alightStopName

        return VStack(alignment: .leading, spacing: 14) {
            // Route label
            if let origin, let destination {
                HStack(spacing: 5) {
                    Text(origin)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(destination)
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.muted)
                .tracking(0.4)
                .textCase(.uppercase)
            }

            // Times
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                timeDisplay(
                    scheduled: trip.startTime,
                    estimated: trip.legs.first(where: { $0.isTimedLeg })?.estimatedDepartureTime,
                    delay: depDelay
                )
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(AppTheme.mutedSoft)
                timeDisplay(
                    scheduled: trip.endTime,
                    estimated: trip.legs.last(where: { $0.isTimedLeg })?.estimatedArrivalTime,
                    delay: arrDelay
                )
            }

            // Meta pills
            HStack(spacing: 8) {
                metaPill(
                    icon: "clock",
                    text: formatter.calculateDuration(start: trip.startTime, end: trip.endTime)
                )
                if trip.interchanges == 0 {
                    metaPill(icon: "arrow.forward", text: "Direkt")
                } else {
                    metaPill(
                        icon: "arrow.triangle.swap",
                        text: "\(trip.interchanges) Umstieg\(trip.interchanges == 1 ? "" : "e")"
                    )
                }
                if maxDelay >= 2 {
                    metaPill(
                        icon: maxDelay >= 5 ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark",
                        text: "+\(maxDelay) Min",
                        accent: maxDelay >= 5 ? .red : .orange
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                .shadow(color: AppTheme.shadowColor(), radius: 8, y: 4)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
        )
        .padding(.horizontal)
        .padding(.top, 20)
    }

    @ViewBuilder
    private func timeDisplay(scheduled: String, estimated: String?, delay: Int?) -> some View {
        if let delay, delay > 0, let est = estimated {
            VStack(alignment: .leading, spacing: 1) {
                Text(formatter.formatTime(scheduled))
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.mutedSoft)
                    .strikethrough(true, color: AppTheme.mutedSoft)
                Text(formatter.formatTime(est))
                    .font(AppTheme.displayFont(size: 36))
                    .foregroundColor(.red)
            }
        } else {
            Text(formatter.formatTime(scheduled))
                .font(AppTheme.displayFont(size: 36))
                .foregroundColor(AppTheme.inkAdaptive(colorScheme))
        }
    }

    @ViewBuilder
    private func metaPill(icon: String, text: String, accent: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(accent ?? AppTheme.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(accent != nil
                      ? (accent ?? .orange).opacity(0.08)
                      : AppTheme.surfaceStrongAdaptive(colorScheme))
                .overlay(
                    accent != nil
                    ? Capsule().stroke((accent ?? .orange).opacity(0.2), lineWidth: 1)
                    : nil
                )
        )
    }

    // MARK: - Live Activity Row (compact)

    @available(iOS 16.2, *)
    @ViewBuilder
    private var liveActivityRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isLiveActivityActive ? Color.green.opacity(0.12) : AppTheme.surfaceStrongAdaptive(colorScheme))
                    .frame(width: 36, height: 36)
                Image(systemName: isLiveActivityActive ? "bell.badge.fill" : "bell")
                    .font(.system(size: 15))
                    .foregroundColor(isLiveActivityActive ? .green : AppTheme.muted)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Live-Verfolgung")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.inkAdaptive(colorScheme))
                Text(isLiveActivityActive
                     ? "Aktiv · Dynamic Island & Sperrbildschirm"
                     : "Echtzeit-Updates auf dem Sperrbildschirm")
                    .font(.caption)
                    .foregroundColor(isLiveActivityActive ? .green : AppTheme.muted)
            }

            Spacer()

            Toggle("", isOn: $isLiveActivityActive)
                .labelsHidden()
                .tint(.green)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                .shadow(color: AppTheme.shadowColor(), radius: 6, y: 3)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
        )
        .padding(.horizontal)
        .onChange(of: isLiveActivityActive) { _, newValue in
            handleToggleChange(newValue)
        }
    }

    // MARK: - Map Section

    private var mapSection: some View {
        VStack(spacing: 0) {
            ZStack {
                if mapVM.isLoading {
                    AppTheme.surfaceStrongAdaptive(colorScheme)
                    ProgressView()
                        .tint(AppTheme.muted)
                } else {
                    TransitMapViewRepresentable(
                        origin: mapVM.originItem,
                        destination: mapVM.destinationItem,
                        route: mapVM.route,
                        stopItems: mapVM.stopItems,
                        transferItems: mapVM.transferItems,
                        transitPolylines: mapVM.transitPolylines,
                        bottomInset: 60
                    )
                    .onTapGesture { showFullMap = true }

                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(7)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(10)
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 200)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 20))
            .sheet(isPresented: $showFullMap) {
                FullMapView(mapVM: mapVM, legs: trip.legs)
            }

            Button(action: openInAppleMaps) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 0.25, green: 0.55, blue: 1.0))
                    Text("In Apple Karten navigieren")
                        .font(.subheadline)
                        .foregroundColor(Color(red: 0.25, green: 0.55, blue: 1.0))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.mutedSoft)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                .shadow(color: AppTheme.shadowColor(), radius: 6, y: 3)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
        )
        .padding(.horizontal)
    }

    private func openInAppleMaps() {
        let origin = trip.legs.first(where: { $0.isTimedLeg })?.boardStopName ?? ""
        let destination = trip.legs.last(where: { $0.isTimedLeg })?.alightStopName ?? ""
        var components = URLComponents(string: "maps://")!
        components.queryItems = [
            URLQueryItem(name: "saddr", value: origin),
            URLQueryItem(name: "daddr", value: destination),
            URLQueryItem(name: "dirflg", value: "r")
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Helpers

    @available(iOS 16.2, *)
    private func handleToggleChange(_ newValue: Bool) {
        guard didAppear else { return }
        Task {
            if newValue {
                LiveActivityState.shared.setTripActive(trip.id.uuidString, isActive: true)
                TripDataManager.shared.saveTripData(trip)
                await liveActivityManager.startActivity(for: trip, accessToken: authService.accessToken ?? "")
            } else {
                LiveActivityState.shared.setTripActive(trip.id.uuidString, isActive: false)
                TripDataManager.shared.removeTripData(for: trip.id.uuidString)
                await liveActivityManager.endActivity(tripId: trip.id.uuidString)
            }
        }
    }

    private func getFirstLegDelay() -> Int? {
        guard let leg = trip.legs.first(where: { $0.isTimedLeg }),
              let s = leg.departureTime, let e = leg.estimatedDepartureTime else { return nil }
        return formatter.calculateDelay(timetabled: s, estimated: e)
    }

    private func getLastLegDelay() -> Int? {
        guard let leg = trip.legs.last(where: { $0.isTimedLeg }),
              let s = leg.arrivalTime, let e = leg.estimatedArrivalTime else { return nil }
        return formatter.calculateDelay(timetabled: s, estimated: e)
    }

    private func generateShareText() -> String {
        var text = "🚆 RNV Verbindung\n"
        text += "\(formatter.formatTime(trip.startTime)) → \(formatter.formatTime(trip.endTime))"
        text += " (\(formatter.calculateDuration(start: trip.startTime, end: trip.endTime)))\n\n"
        for leg in trip.legs {
            if leg.isTimedLeg {
                text += "🚏 \(formatter.formatTime(leg.departureTime ?? "")) \(leg.boardStopName ?? "?")\n"
                text += "   \(leg.serviceName ?? "?") → \(leg.destinationLabel ?? "")\n"
                text += "🚏 \(formatter.formatTime(leg.arrivalTime ?? "")) \(leg.alightStopName ?? "?")\n\n"
            } else {
                text += "🚶 Fußweg (\(formatter.calculateDuration(start: leg.departureTime ?? "", end: leg.arrivalTime ?? "")))\n\n"
            }
        }
        if trip.interchanges > 0 {
            text += "🔄 \(trip.interchanges) Umstieg\(trip.interchanges == 1 ? "" : "e")\n"
        }
        return text
    }
}

#Preview {
    let mockTrip = DetailedTrip(
        startTime: "2026-01-18T14:30:00.000Z",
        endTime: "2026-01-18T15:15:00.000Z",
        interchanges: 1,
        legs: [
            TripLeg(
                type: .timedLeg, mode: "STRASSENBAHN",
                boardStopName: "Mannheim Hbf", alightStopName: "Heidelberg Bismarckplatz",
                departureTime: "2026-01-18T14:30:00.000Z", arrivalTime: "2026-01-18T14:45:00.000Z",
                estimatedDepartureTime: "2026-01-18T14:33:00.000Z", estimatedArrivalTime: "2026-01-18T14:48:00.000Z",
                serviceType: "STRASSENBAHN", serviceName: "Linie 5",
                serviceDescription: nil, destinationLabel: "Heidelberg Hauptbahnhof"
            ),
            TripLeg(
                type: .continuousLeg, mode: "WALK",
                boardStopName: nil, alightStopName: nil,
                departureTime: "2026-01-18T14:45:00.000Z", arrivalTime: "2026-01-18T14:50:00.000Z",
                estimatedDepartureTime: nil, estimatedArrivalTime: nil,
                serviceType: nil, serviceName: "Fußweg", serviceDescription: nil, destinationLabel: nil
            ),
            TripLeg(
                type: .timedLeg, mode: "BUS",
                boardStopName: "Heidelberg Bismarckplatz", alightStopName: "Neuenheimer Feld",
                departureTime: "2026-01-18T14:50:00.000Z", arrivalTime: "2026-01-18T15:15:00.000Z",
                estimatedDepartureTime: nil, estimatedArrivalTime: nil,
                serviceType: "BUS", serviceName: "Linie 33",
                serviceDescription: nil, destinationLabel: "Rohrbach"
            )
        ]
    )
    TripDetailView(trip: mockTrip, authService: AuthService(), liveActivityManager: LiveActivityManager())
        .preferredColorScheme(.light)
}
