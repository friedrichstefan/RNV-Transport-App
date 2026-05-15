//
//  PlannedTripDetailSheet.swift
//  RNV-Transport-App
//

import SwiftUI

struct PlannedTripDetailSheet: View {
    let tripId: String
    let tripData: TripData
    let onEnd: () -> Void

    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let formatter = DateFormattingHelper.shared

    // MARK: - Phase

    private var tripPhase: TripPhase {
        let now = Date()
        if formatter.isBeforeDeparture(tripData.startTime, at: now) { return .beforeDeparture }
        if formatter.isArrived(tripData.endTime, at: now) { return .arrived }
        return .duringJourney
    }

    private var isLiveActive: Bool {
        LiveActivityState.shared.isTripActive(tripId)
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    phaseStatusBanner
                    overviewCard
                    routeTimelineCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(AppTheme.canvasAdaptive(colorScheme).ignoresSafeArea())
            .navigationTitle("Fahrtdetails")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.mutedSoft)
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onEnd()
                        dismiss()
                    } label: {
                        Text("Beenden")
                            .foregroundColor(.red)
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Phase Status Banner

    @ViewBuilder
    private var phaseStatusBanner: some View {
        HStack(spacing: 10) {
            switch tripPhase {
            case .beforeDeparture:
                Image(systemName: "clock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Vor Abfahrt")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.cyan)
                    if let depDate = formatter.parseISO8601(tripData.startTime) {
                        let mins = max(0, Int(depDate.timeIntervalSinceNow / 60))
                        Text(mins == 0 ? "Fährt jetzt ab" : "in \(mins) Min · \(formatter.formatTime(tripData.startTime))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.cyan.opacity(0.8))
                    }
                }
                Spacer()

            case .duringJourney:
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Unterwegs")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.green)
                    Text("Ankunft \(formatter.formatTime(tripData.endTime))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green.opacity(0.8))
                }
                Spacer()

            case .arrived:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Angekommen")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.green)
                    Text(tripData.endStation)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tripPhase == .beforeDeparture
                      ? Color.cyan.opacity(0.08)
                      : Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tripPhase == .beforeDeparture
                                ? Color.cyan.opacity(0.25)
                                : Color.green.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Overview Card

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // From → To label
            HStack(spacing: 5) {
                Text(tripData.startStation)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .textCase(.uppercase)
                    .tracking(0.3)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.mutedSoft)
                Text(tripData.endStation)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .textCase(.uppercase)
                    .tracking(0.3)
            }

            // Big times
            HStack(spacing: 10) {
                Text(formatter.formatTime(tripData.startTime))
                    .font(AppTheme.displayFont(size: 38))
                    .foregroundStyle(AppTheme.inkAdaptive(colorScheme))
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(AppTheme.mutedSoft)
                Text(formatter.formatTime(tripData.endTime))
                    .font(AppTheme.displayFont(size: 38))
                    .foregroundStyle(AppTheme.inkAdaptive(colorScheme))
                Spacer()
            }

            // Meta pills row
            HStack(spacing: 8) {
                metaPill(
                    icon: "clock",
                    text: formatter.calculateDuration(start: tripData.startTime, end: tripData.endTime)
                )
                if tripData.interchanges == 0 {
                    metaPill(icon: "arrow.forward", text: "Direkt")
                } else {
                    metaPill(
                        icon: "arrow.triangle.swap",
                        text: "\(tripData.interchanges) Umstieg\(tripData.interchanges == 1 ? "" : "e")"
                    )
                }

                if isLiveActive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Live aktiv")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.08))
                            .overlay(Capsule().stroke(Color.green.opacity(0.2), lineWidth: 1))
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
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .medium))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(AppTheme.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(AppTheme.surfaceStrongAdaptive(colorScheme)))
    }

    // MARK: - Route Timeline Card

    private var routeTimelineCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Route")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.bottom, 14)

            ForEach(Array(tripData.legs.enumerated()), id: \.offset) { idx, leg in
                if leg.legType == "continuousLeg" {
                    walkLegRow(leg: leg)
                } else {
                    let timedLegs = tripData.legs.filter { $0.legType != "continuousLeg" }
                    let timedIdx = timedLegs.firstIndex(where: { $0.boardStopName == leg.boardStopName && $0.departureTime == leg.departureTime })
                    let isLastTimed = timedIdx == (timedLegs.count - 1)
                    timedLegRows(leg: leg, isLast: isLastTimed)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                .shadow(color: AppTheme.shadowColor(), radius: 8, y: 4)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
        )
    }

    @ViewBuilder
    private func timedLegRows(leg: TripLegData, isLast: Bool) -> some View {
        let color = TransportIconHelper.getLineColor(for: leg.serviceType, serviceName: leg.serviceName)

        VStack(spacing: 0) {
            // Departure row
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(leg.boardStopName ?? "–")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.inkAdaptive(colorScheme))
                    if let dep = leg.departureTime {
                        Text(formatter.formatTime(dep))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                Spacer()

                // Line badge
                if let st = leg.serviceType, let sn = leg.serviceName {
                    lineBadgeSmall(serviceType: st, serviceName: sn)
                }
            }

            // Timeline connector + destination hint
            HStack(alignment: .center, spacing: 0) {
                Rectangle()
                    .fill(color.opacity(0.3))
                    .frame(width: 2, height: 32)
                    .padding(.leading, 9)

                if let dest = leg.destinationLabel {
                    Text("→ \(dest)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.mutedSoft)
                        .lineLimit(1)
                        .padding(.leading, 10)
                }

                Spacer()
            }

            // Arrival row
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 10, height: 10)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(leg.alightStopName ?? "–")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isLast ? AppTheme.inkAdaptive(colorScheme) : AppTheme.muted)
                    if let arr = leg.arrivalTime {
                        Text(formatter.formatTime(arr))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                Spacer()
            }
        }
        .padding(.bottom, isLast ? 0 : 4)
    }

    @ViewBuilder
    private func walkLegRow(leg: TripLegData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.mutedSoft)
                .frame(width: 20, alignment: .center)

            let duration = formatter.calculateDuration(
                start: leg.departureTime ?? "",
                end: leg.arrivalTime ?? ""
            )
            Text("Fußweg · \(duration)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.mutedSoft)
        }
        .padding(.vertical, 6)
    }

    private func lineBadgeSmall(serviceType: String, serviceName: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: TransportIconHelper.getTransportIcon(for: serviceType, serviceName: serviceName))
                .font(.system(size: 8, weight: .bold))
            Text(TransportIconHelper.getShortLineName(from: serviceName))
                .font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(TransportIconHelper.getLineColor(for: serviceType, serviceName: serviceName))
        )
    }
}
