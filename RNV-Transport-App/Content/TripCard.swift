//
//  TripCard.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import SwiftUI

struct TripCard: View {
    let trip: DetailedTrip

    @Environment(\.colorScheme) private var colorScheme
    private let formatter = DateFormattingHelper.shared

    private var isPast: Bool {
        guard let endDate = formatter.parseISO8601(trip.endTime) else { return false }
        return endDate < Date()
    }

    private var minutesUntilDeparture: Int? {
        let depTime = trip.legs.first(where: { $0.isTimedLeg })?.estimatedDepartureTime ?? trip.startTime
        guard let depDate = formatter.parseISO8601(depTime) else { return nil }
        let mins = Int(depDate.timeIntervalSince(Date()) / 60)
        return mins >= 0 ? mins : nil
    }

    private var primaryLineColor: Color {
        guard let firstLeg = trip.legs.first(where: { $0.isTimedLeg }) else {
            return AppTheme.primaryColor
        }
        return TransportIconHelper.getLineColor(for: firstLeg.serviceType, serviceName: firstLeg.serviceName)
    }

    private var departureDelay: Int? { getFirstLegDelay() }
    private var arrivalDelay: Int? { getLastLegDelay() }

    private var maxDelay: Int? {
        let m = max(departureDelay ?? 0, arrivalDelay ?? 0)
        return m > 0 ? m : nil
    }

    private var timedLegs: [TripLeg] {
        trip.legs.filter { $0.isTimedLeg }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isPast ? AppTheme.hairlineStrong : primaryLineColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    timeRow
                    Spacer()
                    statusColumn
                }

                metaRow
                transportLinesRow
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
        .background(
            isPast
                ? AppTheme.surfaceStrongAdaptive(colorScheme)
                : AppTheme.surfaceCardAdaptive(colorScheme)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
        .shadow(
            color: AppTheme.shadowColor(isPast: isPast),
            radius: isPast ? 4 : 8,
            y: isPast ? 1 : 4
        )
        .opacity(isPast ? 0.58 : 1.0)
        .padding(.horizontal)
    }

    // MARK: - Time Row

    private var timeRow: some View {
        HStack(spacing: 8) {
            timeView(scheduled: trip.startTime, estimated: getFirstLegEstimatedDeparture(), delay: departureDelay)

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.5))

            timeView(scheduled: trip.endTime, estimated: getLastLegEstimatedArrival(), delay: arrivalDelay)
        }
    }

    @ViewBuilder
    private func timeView(scheduled: String, estimated: String?, delay: Int?) -> some View {
        if let delay = delay, delay > 0, let est = estimated {
            VStack(alignment: .leading, spacing: 1) {
                Text(formatter.formatTime(scheduled))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .strikethrough(true, color: .red.opacity(0.5))
                Text(formatter.formatTime(est))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.red)
            }
        } else {
            Text(formatter.formatTime(scheduled))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Status Column

    @ViewBuilder
    private var statusColumn: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if isPast {
                statusBadge(text: "Abgefahren", icon: "clock.badge.xmark", color: .secondary, bg: AppTheme.surfaceStrong)
            } else if let mins = minutesUntilDeparture, mins <= 60 {
                statusBadge(
                    text: mins == 0 ? "Jetzt" : "in \(mins) Min",
                    icon: mins <= 5 ? "figure.run" : "timer",
                    color: mins <= 5 ? .red : AppTheme.primaryColor,
                    bg: (mins <= 5 ? Color.red : AppTheme.primaryColor).opacity(0.12)
                )
            }

            if let delay = maxDelay, delay >= 2 {
                statusBadge(
                    text: "+\(delay) Min",
                    icon: delay >= 5 ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark",
                    color: delay >= 5 ? .red : .orange,
                    bg: (delay >= 5 ? Color.red : Color.orange).opacity(0.12)
                )
            } else if !isPast {
                statusBadge(text: "Pünktlich", icon: "checkmark.circle.fill", color: .green, bg: Color.green.opacity(0.12))
            }
        }
    }

    @ViewBuilder
    private func statusBadge(text: String, icon: String, color: Color, bg: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.caption2).fontWeight(.semibold)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(bg))
    }

    // MARK: - Meta Row

    private var metaRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(formatter.calculateDuration(start: trip.startTime, end: trip.endTime))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("·")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.4))

            if trip.interchanges == 0 {
                HStack(spacing: 3) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 10))
                    Text("Direkt")
                        .font(.subheadline)
                }
                .foregroundColor(AppTheme.primaryColor)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 10))
                    Text("\(trip.interchanges)× Umstieg")
                        .font(.subheadline)
                }
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Transport Lines

    private var transportLinesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(timedLegs.enumerated()), id: \.offset) { index, leg in
                    if leg.serviceName != nil {
                        lineBadge(leg: leg)
                        if index < timedLegs.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func lineBadge(leg: TripLeg) -> some View {
        let isSBahn = TransportIconHelper.isSBahnLine(serviceType: leg.serviceType, serviceName: leg.serviceName)
        let lineColor = TransportIconHelper.getLineColor(for: leg.serviceType, serviceName: leg.serviceName)
        let hasDelay = (getLegDelay(leg) ?? 0) > 0

        HStack(spacing: 4) {
            Image(systemName: TransportIconHelper.getTransportIcon(for: leg.serviceType, serviceName: leg.serviceName))
                .font(.system(size: isSBahn ? 14 : 10))
            Text(TransportIconHelper.getShortLineName(from: leg.serviceName))
                .font(.caption)
                .fontWeight(.bold)
        }
        .foregroundColor(isSBahn ? .green : .white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Group {
                if isSBahn {
                    Capsule()
                        .fill(colorScheme == .dark ? AppTheme.surfaceDarkElevated : AppTheme.surfaceCard)
                        .overlay(Capsule().stroke(hasDelay ? Color.red : Color.green, lineWidth: 1.5))
                } else if hasDelay {
                    Capsule()
                        .fill(lineColor)
                        .overlay(Capsule().stroke(Color.red, lineWidth: 1.5))
                } else {
                    Capsule().fill(lineColor)
                }
            }
        )
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
        trip.legs.first(where: { $0.isTimedLeg })?.estimatedDepartureTime
    }

    private func getLastLegEstimatedArrival() -> String? {
        trip.legs.last(where: { $0.isTimedLeg })?.estimatedArrivalTime
    }

    private func getLegDelay(_ leg: TripLeg) -> Int? {
        guard let scheduled = leg.departureTime, let estimated = leg.estimatedDepartureTime else { return nil }
        return formatter.calculateDelay(timetabled: scheduled, estimated: estimated)
    }
}
