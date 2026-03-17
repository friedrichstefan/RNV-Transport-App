//
//  TripCard.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import SwiftUI

struct TripCard: View {
    let trip: DetailedTrip
    let graphQLService: GraphQLService
    let authService: AuthService

    @ObservedObject var liveActivityManager: LiveActivityManager
    @State private var isLiveActivityActive = false
    @State private var stateCheckTask: Task<Void, Never>?

    @Environment(\.colorScheme) private var colorScheme

    private let formatter = DateFormattingHelper.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    timeDisplayWithDelay

                    Text(formatter.calculateDuration(start: trip.startTime, end: trip.endTime))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                statusBadges
            }

            if hasSignificantDelay {
                delayInfoBanner
            }

            transportLinesWithDestinations

            Divider()
                .padding(.vertical, 4)

            if #available(iOS 16.2, *) {
                liveActivitySection
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, y: 4)
        )
        .padding(.horizontal)
    }

    // MARK: - Time Display with Delay

    @ViewBuilder
    private var timeDisplayWithDelay: some View {
        let departureDelay = getFirstLegDelay()
        let arrivalDelay = getLastLegDelay()

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let delay = departureDelay, delay > 0 {
                    HStack(spacing: 6) {
                        Text(formatter.formatTime(trip.startTime))
                            .font(.title2)
                            .fontWeight(.bold)
                            .strikethrough(true, color: .red)
                            .foregroundColor(.secondary)

                        Text(getEstimatedTime(trip.startTime, delay: delay))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                } else {
                    Text(formatter.formatTime(trip.startTime))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            }

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .trailing, spacing: 2) {
                if let delay = arrivalDelay, delay > 0 {
                    HStack(spacing: 6) {
                        Text(formatter.formatTime(trip.endTime))
                            .font(.title2)
                            .fontWeight(.bold)
                            .strikethrough(true, color: .red)
                            .foregroundColor(.secondary)

                        Text(getEstimatedTime(trip.endTime, delay: delay))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                } else {
                    Text(formatter.formatTime(trip.endTime))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            }
        }
    }

    // MARK: - Status Badges

    @ViewBuilder
    private var statusBadges: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let maxDelay = getMaxDelay(), maxDelay > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 10))
                    Text("+\(maxDelay) Min")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(maxDelay >= 5 ? Color.red : Color.orange)
                )
            }

            if trip.interchanges == 0 {
                Text("Direkt")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.green))
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.caption2)
                    Text("\(trip.interchanges)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.orange))
            }
        }
    }

    // MARK: - Delay Information Banner

    @ViewBuilder
    private var delayInfoBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 14))

            Text(getDelayMessage())
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.red)

            Spacer()

            if getDelayedLegsCount() > 1 {
                Text("\(getDelayedLegsCount()) Teilstrecken betroffen")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Transport Lines

    @ViewBuilder
    private var transportLinesWithDestinations: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(trip.legs.filter { $0.isTimedLeg }) { leg in
                    if let serviceName = leg.serviceName {
                        VStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: TransportIconHelper.getTransportIcon(for: leg.serviceType))
                                    .font(.caption2)
                                Text(TransportIconHelper.getShortLineName(from: serviceName))
                                    .font(.caption)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(TransportIconHelper.getLineColor(for: leg.serviceType)))

                            if let destination = leg.destinationLabel {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)

                                    Text(destination)
                                        .font(.system(size: 9))
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)

                                    if let legDelay = getLegDelay(leg), legDelay > 0 {
                                        Text("+\(legDelay)")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.red))
                                    }
                                }
                                .lineLimit(1)
                                .frame(maxWidth: 140)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Live Activity Section

    @available(iOS 16.2, *)
    @ViewBuilder
    private var liveActivitySection: some View {
        HStack(spacing: 12) {
            Image(systemName: isLiveActivityActive ? "bell.badge.fill" : "bell")
                .font(.title3)
                .foregroundColor(isLiveActivityActive ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Live-Verfolgung")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if isLiveActivityActive {
                    Text("Aktiv mit Echtzeit-Updates")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .lineLimit(1)
                } else {
                    Text("Für Live-Updates aktivieren")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Toggle("", isOn: $isLiveActivityActive)
                .labelsHidden()
                .tint(.green)
        }
        .padding(.top, 4)
        .onChange(of: isLiveActivityActive) { newValue in
            handleToggleChange(newValue)
        }
        .onAppear {
            isLiveActivityActive = LiveActivityState.shared.isTripActive(trip.id.uuidString)
            startStateCheckTask()
        }
        .onDisappear {
            stateCheckTask?.cancel()
            stateCheckTask = nil
        }

        if let error = liveActivityManager.lastError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private var hasSignificantDelay: Bool {
        if let delay = getFirstLegDelay(), delay >= 3 { return true }
        if let delay = getLastLegDelay(), delay >= 3 { return true }
        return false
    }

    private func getFirstLegDelay() -> Int? {
        guard let firstTimedLeg = trip.legs.first(where: { $0.isTimedLeg }),
              let scheduled = firstTimedLeg.departureTime,
              let estimated = firstTimedLeg.estimatedDepartureTime else { return nil }

        return formatter.calculateDelay(timetabled: scheduled, estimated: estimated)
    }

    private func getLastLegDelay() -> Int? {
        guard let lastTimedLeg = trip.legs.last(where: { $0.isTimedLeg }),
              let scheduled = lastTimedLeg.arrivalTime,
              let estimated = lastTimedLeg.estimatedArrivalTime else { return nil }

        return formatter.calculateDelay(timetabled: scheduled, estimated: estimated)
    }

    private func getMaxDelay() -> Int? {
        let depDelay = getFirstLegDelay() ?? 0
        let arrDelay = getLastLegDelay() ?? 0
        let maxDelay = max(depDelay, arrDelay)
        return maxDelay > 0 ? maxDelay : nil
    }

    private func getLegDelay(_ leg: TripLeg) -> Int? {
        if let scheduled = leg.departureTime,
           let estimated = leg.estimatedDepartureTime {
            return formatter.calculateDelay(timetabled: scheduled, estimated: estimated)
        }
        return nil
    }

    private func getDelayedLegsCount() -> Int {
        return trip.legs.filter { leg in
            if let delay = getLegDelay(leg), delay > 0 {
                return true
            }
            return false
        }.count
    }

    private func getDelayMessage() -> String {
        let depDelay = getFirstLegDelay() ?? 0
        let arrDelay = getLastLegDelay() ?? 0
        let maxDelay = max(depDelay, arrDelay)

        if maxDelay >= 10 {
            return "Erhebliche Verspätung: +\(maxDelay) Minuten"
        } else if maxDelay >= 5 {
            return "Verspätung: +\(maxDelay) Minuten"
        } else {
            return "Geringfügige Verspätung: +\(maxDelay) Minuten"
        }
    }

    private func getEstimatedTime(_ isoString: String, delay: Int) -> String {
        guard let date = formatter.parseISO8601(isoString) else { return isoString }
        let delayedDate = date.addingTimeInterval(TimeInterval(delay * 60))
        return formatter.formatTimeFromDate(delayedDate)
    }

    private func handleToggleChange(_ newValue: Bool) {
        Task {
            if newValue {
                print("🟢 [UI] Live Activity aktiviert für Trip: \(trip.id)")
                LiveActivityState.shared.setTripActive(trip.id.uuidString, isActive: true)
                TripDataManager.shared.saveTripData(trip)
                await liveActivityManager.startActivity(for: trip, accessToken: authService.accessToken ?? "")
            } else {
                print("🔴 [UI] Live Activity deaktiviert für Trip: \(trip.id)")
                LiveActivityState.shared.setTripActive(trip.id.uuidString, isActive: false)
                TripDataManager.shared.removeTripData(for: trip.id.uuidString)
                await liveActivityManager.endActivity(tripId: trip.id.uuidString)
            }
        }
    }

    private func startStateCheckTask() {
        stateCheckTask?.cancel()
        stateCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                let currentState = LiveActivityState.shared.isTripActive(trip.id.uuidString)
                if currentState != isLiveActivityActive {
                    print("🔄 [SYNC] State von Widget erkannt: \(currentState)")
                    isLiveActivityActive = currentState
                }
            }
        }
    }
}
