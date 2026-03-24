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
    @State private var didAppear = false

    @Environment(\.colorScheme) private var colorScheme

    private let formatter = DateFormattingHelper.shared

    /// Verbindung ist abgefahren, wenn die Ankunftszeit in der Vergangenheit liegt
    private var isPast: Bool {
        guard let endDate = formatter.parseISO8601(trip.endTime) else { return false }
        return endDate < Date()
    }

    /// Minuten bis zur Abfahrt (nil wenn bereits abgefahren)
    private var minutesUntilDeparture: Int? {
        let depTime = getFirstLegEstimatedDeparture() ?? trip.startTime
        guard let depDate = formatter.parseISO8601(depTime) else { return nil }
        let mins = Int(depDate.timeIntervalSince(Date()) / 60)
        return mins >= 0 ? mins : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: Time + Status
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    timeDisplay
                    durationRow
                }

                Spacer()

                statusBadges
            }

            // Delay banner (only for significant delays)
            if let maxDelay = getMaxDelay(), maxDelay >= 2 {
                delayInfoBanner(delay: maxDelay)
            }

            // Transport lines
            transportLinesSection

            if !isPast {
                Divider()
                    .padding(.vertical, 4)

                if #available(iOS 16.2, *) {
                    liveActivitySection
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(isPast
                    ? Color(colorScheme == .dark ? .systemGray5 : .systemGray6)
                    : Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                .shadow(
                    color: .black.opacity(isPast ? 0.04 : (colorScheme == .dark ? 0.3 : 0.08)),
                    radius: isPast ? 3 : 8,
                    y: isPast ? 1 : 4
                )
        )
        .opacity(isPast ? 0.58 : 1.0)
        .padding(.horizontal)
    }

    // MARK: - Time Display

    @ViewBuilder
    private var timeDisplay: some View {
        let departureDelay = getFirstLegDelay()
        let arrivalDelay = getLastLegDelay()

        HStack(spacing: 6) {
            // Departure time
            timeWithDelay(
                scheduled: trip.startTime,
                estimatedISO: getFirstLegEstimatedDeparture(),
                delay: departureDelay
            )

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 2)

            // Arrival time
            timeWithDelay(
                scheduled: trip.endTime,
                estimatedISO: getLastLegEstimatedArrival(),
                delay: arrivalDelay
            )
        }
    }

    @ViewBuilder
    private func timeWithDelay(scheduled: String, estimatedISO: String?, delay: Int?) -> some View {
        if let delay = delay, delay > 0, let estimated = estimatedISO {
            VStack(alignment: .leading, spacing: 1) {
                Text(formatter.formatTime(scheduled))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .strikethrough(true, color: .red.opacity(0.6))

                HStack(spacing: 4) {
                    Text(formatter.formatTime(estimated))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.red)

                    Text("+\(delay)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(delay >= 5 ? Color.red : Color.orange))
                }
            }
        } else {
            Text(formatter.formatTime(scheduled))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
    }

    // MARK: - Duration Row

    @ViewBuilder
    private var durationRow: some View {
        let depDelay = getFirstLegDelay() ?? 0
        let arrDelay = getLastLegDelay() ?? 0
        let hasDelay = depDelay > 0 || arrDelay > 0

        HStack(spacing: 6) {
            Text(formatter.calculateDuration(start: trip.startTime, end: trip.endTime))
                .font(.subheadline)
                .foregroundColor(.secondary)

            if hasDelay, let estDep = getFirstLegEstimatedDeparture(), let estArr = getLastLegEstimatedArrival() {
                let realDuration = formatter.calculateDuration(start: estDep, end: estArr)
                if realDuration != formatter.calculateDuration(start: trip.startTime, end: trip.endTime) {
                    Text("(real \(realDuration))")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Status Badges

    @ViewBuilder
    private var statusBadges: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Countdown-Badge: "in X Min"
            if !isPast, let mins = minutesUntilDeparture, mins <= 60 {
                HStack(spacing: 3) {
                    Image(systemName: mins <= 5 ? "figure.run" : "timer")
                        .font(.system(size: 10))
                    Text(mins == 0 ? "Jetzt" : "in \(mins) Min")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundColor(mins <= 5 ? .red : AppTheme.primaryColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(mins <= 5 ? Color.red.opacity(0.12) : AppTheme.primaryColor.opacity(0.12))
                )
            }

            // Abgefahren-Badge für vergangene Verbindungen
            if isPast {
                HStack(spacing: 3) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 10))
                    Text("Abgefahren")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color(.systemGray5))
                )
            } else if getMaxDelay() == nil {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("Pünktlich")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.green.opacity(0.12))
                )
            }

            // Interchange badge
            if trip.interchanges == 0 {
                HStack(spacing: 3) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 10))
                    Text("Direkt")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(AppTheme.primaryColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(AppTheme.primaryColor.opacity(0.12))
                )
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 10))
                    Text("\(trip.interchanges)× Umstieg")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(.systemGray5))
                )
            }
        }
    }

    // MARK: - Delay Info Banner

    @ViewBuilder
    private func delayInfoBanner(delay: Int) -> some View {
        let delayedLegs = getDelayedLegsCount()
        let bannerColor: Color = delay >= 5 ? .red : .orange

        HStack(spacing: 8) {
            Image(systemName: delay >= 5 ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark")
                .foregroundColor(bannerColor)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 1) {
                Text("Verspätung: +\(delay) Min.")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(bannerColor)

                if delayedLegs > 1 {
                    Text("\(delayedLegs) Teilstrecken betroffen")
                        .font(.caption2)
                        .foregroundColor(bannerColor.opacity(0.8))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(bannerColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(bannerColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Transport Lines

    @ViewBuilder
    private var transportLinesSection: some View {
        let timedLegs = trip.legs.filter { $0.isTimedLeg }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(timedLegs.enumerated()), id: \.offset) { index, leg in
                    if let serviceName = leg.serviceName {
                        legBadge(leg: leg, serviceName: serviceName)

                        // Arrow between legs
                        if index < timedLegs.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func legBadge(leg: TripLeg, serviceName: String) -> some View {
        let legDelay = getLegDelay(leg)
        let isSBahn = TransportIconHelper.isSBahnLine(serviceType: leg.serviceType, serviceName: leg.serviceName)
        let lineColor = TransportIconHelper.getLineColor(for: leg.serviceType, serviceName: leg.serviceName)

        VStack(spacing: 4) {
            // Line badge with integrated delay
            HStack(spacing: 4) {
                Image(systemName: TransportIconHelper.getTransportIcon(for: leg.serviceType, serviceName: leg.serviceName))
                    .font(.system(size: isSBahn ? 15 : 10))
                Text(TransportIconHelper.getShortLineName(from: serviceName))
                    .font(.caption)
                    .fontWeight(.bold)

                if let delay = legDelay, delay > 0 {
                    Text("+\(delay)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSBahn ? Color.green.opacity(0.15) : Color.white.opacity(0.3))
                        )
                }
            }
            .foregroundColor(isSBahn ? .green : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Group {
                    if isSBahn {
                        Capsule()
                            .fill(Color.white)
                            .overlay(Capsule().stroke(Color.green, lineWidth: 1.5))
                    } else {
                        Capsule().fill(lineColor)
                            .overlay(
                                legDelay != nil && legDelay! > 0 ?
                                Capsule().stroke(Color.red, lineWidth: 1.5) : nil
                            )
                    }
                }
            )

            // Destination label
            if let destination = leg.destinationLabel {
                Text(destination)
                    .font(.system(size: 9))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
            }
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
        .onChange(of: isLiveActivityActive) { _, newValue in
            handleToggleChange(newValue)
        }
        .onAppear {
            isLiveActivityActive = LiveActivityState.shared.isTripActive(trip.id.uuidString)
            didAppear = true
        }
        .onReceive(NotificationCenter.default.publisher(for: LiveActivityState.activeTripsDidChangeNotification)) { _ in
            let currentState = LiveActivityState.shared.isTripActive(trip.id.uuidString)
            if currentState != isLiveActivityActive {
                #if DEBUG
                print("🔄 [SYNC] State-Änderung erkannt für Trip \(trip.id): \(currentState)")
                #endif
                isLiveActivityActive = currentState
            }
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

    private func getFirstLegEstimatedDeparture() -> String? {
        return trip.legs.first(where: { $0.isTimedLeg })?.estimatedDepartureTime
    }

    private func getLastLegEstimatedArrival() -> String? {
        return trip.legs.last(where: { $0.isTimedLeg })?.estimatedArrivalTime
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

    private func handleToggleChange(_ newValue: Bool) {
        guard didAppear else { return }
        Task {
            if newValue {
                #if DEBUG
                print("🟢 [UI] Live Activity aktiviert für Trip: \(trip.id)")
                #endif
                LiveActivityState.shared.setTripActive(trip.id.uuidString, isActive: true)
                TripDataManager.shared.saveTripData(trip)
                await liveActivityManager.startActivity(for: trip, accessToken: authService.accessToken ?? "")
            } else {
                #if DEBUG
                print("🔴 [UI] Live Activity deaktiviert für Trip: \(trip.id)")
                #endif
                LiveActivityState.shared.setTripActive(trip.id.uuidString, isActive: false)
                TripDataManager.shared.removeTripData(for: trip.id.uuidString)
                await liveActivityManager.endActivity(tripId: trip.id.uuidString)
            }
        }
    }

}