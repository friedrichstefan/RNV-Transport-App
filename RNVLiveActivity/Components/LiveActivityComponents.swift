//
//  LiveActivityComponents.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 13.01.26.
//

import SwiftUI
import ActivityKit
import WidgetKit
import AppIntents

// MARK: - Local Phase Calculator

/// Berechnet die Phase lokal basierend auf der aktuellen Zeit,
/// damit der Übergang sofort sichtbar ist (ohne auf Server-Update zu warten).
struct LocalPhaseCalculator {
    enum LocalPhase {
        case beforeDeparture
        case duringJourney
        case arrived
    }

    static func calculate(
        departureTimeISO: String,
        arrivalTimeISO: String,
        delay: Int?,
        currentTime: Date
    ) -> LocalPhase {
        guard let departureDate = DateCalculationHelper.parseDate(departureTimeISO),
              let arrivalDate = DateCalculationHelper.parseDate(arrivalTimeISO) else {
            return .duringJourney
        }

        let effectiveDeparture: Date
        let effectiveArrival: Date

        if let d = delay, d > 0 {
            effectiveDeparture = departureDate.addingTimeInterval(TimeInterval(d * 60))
            effectiveArrival = arrivalDate.addingTimeInterval(TimeInterval(d * 60))
        } else {
            effectiveDeparture = departureDate
            effectiveArrival = arrivalDate
        }

        if currentTime < effectiveDeparture {
            return .beforeDeparture
        }

        if currentTime >= effectiveArrival {
            return .arrived
        }

        return .duringJourney
    }
}

// MARK: - Journey Progress Bar

struct JourneyProgressBar: View {
    let departureDate: Date
    let arrivalDate: Date
    let serviceType: String
    let lineName: String
    let delay: Int?
    let currentTime: Date

    private var effectiveDepartureDate: Date {
        if let delay = delay, delay > 0 {
            return departureDate.addingTimeInterval(TimeInterval(delay * 60))
        }
        return departureDate
    }

    private var progress: CGFloat {
        if currentTime < effectiveDepartureDate {
            return 0
        }
        let total = arrivalDate.timeIntervalSince(effectiveDepartureDate)
        guard total > 0 else { return 1 }
        let elapsed = currentTime.timeIntervalSince(effectiveDepartureDate)
        return CGFloat(min(1.0, max(0.0, elapsed / total)))
    }

    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width
            let indicatorX = barWidth * progress

            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 6)

                // Filled
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.6), accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, barWidth * progress), height: 6)

                // Vehicle indicator
                if progress > 0 && progress < 1 {
                    ZStack {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 22, height: 22)
                            .shadow(color: accentColor.opacity(0.5), radius: 4, x: 0, y: 2)

                        Image(systemName: StyleHelper.getIcon(for: serviceType, serviceName: lineName))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: max(0, min(indicatorX - 11, barWidth - 22)))
                }
            }
        }
        .frame(height: 22)
    }

    private var accentColor: Color {
        if let d = delay, d > 0 { return .orange }
        return StyleHelper.getColor(for: serviceType, serviceName: lineName)
    }
}

// MARK: - Countdown Badge

struct CountdownBadge: View {
    let timeRange: ClosedRange<Date>?
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(color.opacity(0.7))

            if let range = timeRange {
                Text(timerInterval: range, countsDown: true)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(color)
                    .contentTransition(.numericText(countsDown: true))
            } else {
                Text("--:--")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(color.opacity(0.4))
            }
        }
    }
}

// MARK: - Line Badge

struct LineBadge: View {
    let serviceType: String
    let lineName: String
    let size: LineBadgeSize

    private var resolvedServiceName: String { lineName }

    enum LineBadgeSize {
        case small, medium, large
    }

    var body: some View {
        HStack(spacing: iconSpacing) {
            Image(systemName: StyleHelper.getIcon(for: serviceType, serviceName: resolvedServiceName))
                .font(.system(size: iconSize, weight: .bold))
            Text(StyleHelper.getShortName(from: lineName))
                .font(.system(size: textSize, weight: .heavy, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, hPadding)
        .padding(.vertical, vPadding)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(StyleHelper.getColor(for: serviceType, serviceName: resolvedServiceName))
        )
    }

    private var iconSize: CGFloat {
        switch size {
        case .small: return 9
        case .medium: return 12
        case .large: return 14
        }
    }

    private var textSize: CGFloat {
        switch size {
        case .small: return 10
        case .medium: return 13
        case .large: return 15
        }
    }

    private var iconSpacing: CGFloat {
        switch size {
        case .small: return 3
        case .medium: return 4
        case .large: return 5
        }
    }

    private var hPadding: CGFloat {
        switch size {
        case .small: return 6
        case .medium: return 9
        case .large: return 11
        }
    }

    private var vPadding: CGFloat {
        switch size {
        case .small: return 3
        case .medium: return 5
        case .large: return 6
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .small: return 6
        case .medium: return 8
        case .large: return 10
        }
    }
}

// MARK: - Delay Chip

struct DelayChip: View {
    let delay: Int?

    var body: some View {
        if let d = delay, d > 0 {
            Text("+\(d)'")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.orange)
                )
        }
    }
}

// MARK: - Station Timeline Row

struct StationTimelineRow: View {
    let fromStation: String
    let toStation: String
    let departureTimeISO: String
    let arrivalTimeISO: String
    let serviceType: String
    let lineName: String
    let delay: Int?

    var body: some View {
        HStack(spacing: 10) {
            // Timeline dots + line
            VStack(spacing: 0) {
                Circle()
                    .fill(StyleHelper.getColor(for: serviceType, serviceName: lineName))
                    .frame(width: 8, height: 8)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                StyleHelper.getColor(for: serviceType, serviceName: lineName),
                                StyleHelper.getColor(for: serviceType, serviceName: lineName).opacity(0.3)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)

                Circle()
                    .strokeBorder(StyleHelper.getColor(for: serviceType, serviceName: lineName).opacity(0.5), lineWidth: 2)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 12)
            .padding(.vertical, 2)

            // Station info
            VStack(alignment: .leading, spacing: 8) {
                // Departure
                HStack(alignment: .center, spacing: 6) {
                    Text(formattedTime(from: departureTimeISO))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                    DelayChip(delay: delay)
                    Text(fromStation)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                // Arrival
                HStack(alignment: .center, spacing: 6) {
                    Text(formattedTime(from: arrivalTimeISO))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let d = delay, d > 0 {
                        DelayChip(delay: d)
                    }
                    Text(toStation)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
    }

    private func formattedTime(from isoString: String) -> String {
        guard let date = DateCalculationHelper.parseDate(isoString) else { return "--:--" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - Arrived View

struct ArrivedView: View {
    let context: ActivityViewContext<TripLiveActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Angekommen!")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(context.attributes.endStation)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            // Route summary
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("VON")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(context.attributes.startStation)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("NACH")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(context.attributes.endStation)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            Text("Schließt automatisch")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.systemBackground))
    }
}

// MARK: - Content Medium View (Lock Screen)

struct ContentMediumView: View {
    let context: ActivityViewContext<TripLiveActivityAttributes>
    let isBeforeDeparture: Bool
    let currentTime: Date

    private var accentColor: Color {
        StyleHelper.getColor(for: context.state.serviceType, serviceName: context.state.lineName)
    }

    private var hasDelay: Bool {
        (context.state.delay ?? 0) > 0
    }

    /// Lokal berechnete Phase für sofortigen Übergang
    private var localPhase: LocalPhaseCalculator.LocalPhase {
        if context.state.phase == .arrived {
            return .arrived
        }
        return LocalPhaseCalculator.calculate(
            departureTimeISO: context.attributes.departureTimeISO,
            arrivalTimeISO: context.attributes.arrivalTimeISO,
            delay: context.state.delay,
            currentTime: currentTime
        )
    }

    var body: some View {
        if localPhase == .arrived {
            ArrivedView(context: context)
        } else if localPhase == .beforeDeparture {
            beforeDepartureView
        } else {
            duringJourneyView
        }
    }

    // MARK: - Before Departure View (Lock Screen)

    private var beforeDepartureView: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            HStack(alignment: .center, spacing: 16) {
                // Big countdown
                VStack(spacing: 2) {
                    Text("ABFAHRT IN")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(accentColor.opacity(0.8))

                    let range = countdownRange(to: context.attributes.departureTimeISO)
                    if let range = range {
                        Text(timerInterval: range, countsDown: true)
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(hasDelay ? .orange : accentColor)
                            .contentTransition(.numericText(countsDown: true))
                    } else {
                        Text("Jetzt")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundColor(accentColor)
                    }
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 1, height: 44)

                // Route summary
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 7, height: 7)
                        Text(formattedTime(from: context.attributes.departureTimeISO))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                        if hasDelay {
                            Text("+\(context.state.delay ?? 0)'")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundColor(.orange)
                        }
                    }
                    Text(context.attributes.startStation)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 12)

                    HStack(spacing: 5) {
                        Circle()
                            .strokeBorder(accentColor.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 7, height: 7)
                        Text(formattedTime(from: context.attributes.arrivalTimeISO))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text(context.attributes.endStation)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.leading, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(Color(.systemBackground))
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(.primary)
    }

    // MARK: - During Journey View (Lock Screen)

    private var duringJourneyView: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            // Next stop + arrival countdown
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("NÄCHSTER HALT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(context.state.nextStopName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("ANKUNFT IN")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                    let range = countdownRange(to: context.attributes.arrivalTimeISO)
                    if let range = range {
                        Text(timerInterval: range, countsDown: true)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(hasDelay ? .orange : accentColor)
                            .contentTransition(.numericText(countsDown: true))
                    } else {
                        Text("--:--")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Umstieg-Badge (nur wenn weiterer Leg folgt)
            if let transferStop = context.state.nextTransferStopName,
               let transferISO = context.state.nextTransferArrivalISO {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange)
                    Text("Umstieg")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange.opacity(0.85))
                    Text(transferStop)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    if let range = countdownRange(to: transferISO) {
                        HStack(spacing: 2) {
                            Text("in")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(timerInterval: range, countsDown: true)
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.orange)
                                .contentTransition(.numericText(countsDown: true))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            // Progress bar
            JourneyProgressBar(
                departureDate: DateCalculationHelper.parseDate(context.attributes.departureTimeISO) ?? Date(),
                arrivalDate: DateCalculationHelper.parseDate(context.attributes.arrivalTimeISO) ?? Date().addingTimeInterval(1200),
                serviceType: context.state.serviceType,
                lineName: context.state.lineName,
                delay: context.state.delay,
                currentTime: currentTime
            )
            .padding(.horizontal, 16)

            // Departure / arrival time labels below bar
            HStack {
                Text(formattedTime(from: context.attributes.departureTimeISO))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(formattedTime(from: context.attributes.arrivalTimeISO))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 14)
        }
        .background(Color(.systemBackground))
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(.primary)
    }

    private func formattedTime(from isoString: String) -> String {
        guard let date = DateCalculationHelper.parseDate(isoString) else { return "--:--" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            LineBadge(
                serviceType: context.state.serviceType,
                lineName: context.state.lineName,
                size: .medium
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)

            Text(context.state.destination)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            // Status indicator
            statusIndicator
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if localPhase == .duringJourney {
            HStack(spacing: 3) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Unterwegs")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(accentColor))
        } else if hasDelay {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("+\(context.state.delay ?? 0)min")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.orange))
        } else {
            HStack(spacing: 3) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Pünktlich")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.green)
            }
        }
    }

    // MARK: - Compact Countdown (only used during journey now)

    @ViewBuilder
    private var compactCountdown: some View {
        switch localPhase {
        case .beforeDeparture:
            // Should not appear - beforeDeparture has its own view
            EmptyView()

        case .duringJourney:
            let range = countdownRange(to: context.attributes.arrivalTimeISO)
            VStack(spacing: 1) {
                Text("ANK")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.secondary)
                if let range = range {
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(hasDelay ? .orange : accentColor)
                        .contentTransition(.numericText(countsDown: true))
                } else {
                    Text("--:--")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

        case .arrived:
            VStack(spacing: 1) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.green)
                Text("Da!")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.green)
            }
        }
    }

    private func countdownRange(to isoString: String) -> ClosedRange<Date>? {
        if let d = context.state.delay, d > 0 {
            guard let date = DateCalculationHelper.parseDate(isoString) else { return nil }
            let delayed = date.addingTimeInterval(TimeInterval(d * 60))
            guard delayed > currentTime else { return nil }
            return currentTime...delayed
        }
        guard let date = DateCalculationHelper.parseDate(isoString),
              date > currentTime else { return nil }
        return currentTime...date
    }
}

// MARK: - Dynamic Island: Expanded Leading

struct DynamicIslandExpandedLeading: View {
    let serviceType: String
    let lineName: String

    var body: some View {
        LineBadge(
            serviceType: serviceType,
            lineName: lineName,
            size: .small
        )
        .padding(.leading, 4)
    }
}

// MARK: - Dynamic Island: Expanded Trailing

struct DynamicIslandExpandedTrailing: View {
    let delay: Int?
    let phase: TripPhase

    var body: some View {
        Group {
            if phase == .arrived {
                chipView(icon: "checkmark.circle.fill", text: "Da!", color: .green)
            } else if let d = delay, d > 0 {
                chipView(icon: "exclamationmark.triangle.fill", text: "+\(d)'", color: .orange)
            } else {
                chipView(icon: "checkmark.circle.fill", text: "Pünktlich", color: .green)
            }
        }
        .padding(.trailing, 4)
    }

    private func chipView(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color))
    }
}

// MARK: - Dynamic Island: Arrived Bottom View

struct DynamicIslandArrivedBottom: View {
    let startStation: String
    let endStation: String
    let tripId: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Angekommen")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(endStation)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)

            if #available(iOS 16.2, *) {
                Button(intent: EndAllActivitiesIntent()) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Beenden")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red.opacity(0.8))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Dynamic Island: Expanded Bottom

struct DynamicIslandExpandedBottom: View {
    let startStation: String
    let endStation: String
    let departureTimeISO: String
    let arrivalTimeISO: String
    let serviceType: String
    let lineName: String
    let delay: Int?
    let phase: TripPhase
    let tripId: String
    let nextTransferStopName: String?
    let nextTransferArrivalISO: String?
    let currentTime: Date

    /// Lokal berechnete Phase für sofortigen Übergang
    private var localPhase: LocalPhaseCalculator.LocalPhase {
        if phase == .arrived {
            return .arrived
        }
        return LocalPhaseCalculator.calculate(
            departureTimeISO: departureTimeISO,
            arrivalTimeISO: arrivalTimeISO,
            delay: delay,
            currentTime: currentTime
        )
    }

    private var accentColor: Color {
        if let d = delay, d > 0 { return .orange }
        return StyleHelper.getColor(for: serviceType, serviceName: lineName)
    }

    private var hasDelay: Bool {
        (delay ?? 0) > 0
    }

    var body: some View {
        if localPhase == .arrived {
            DynamicIslandArrivedBottom(
                startStation: startStation,
                endStation: endStation,
                tripId: tripId
            )
        } else if localPhase == .beforeDeparture {
            beforeDepartureBottomView
        } else {
            duringJourneyBottomView
        }
    }

    // MARK: - Before Departure Bottom View (Dynamic Island)

    private var beforeDepartureBottomView: some View {
        VStack(spacing: 10) {
            // Prominenter Countdown
            HStack(spacing: 0) {
                // Links: Abfahrtszeit + Station
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(accentColor)
                        Text(formattedTime(from: departureTimeISO))
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                        if hasDelay {
                            Text("+\(delay ?? 0)'")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundColor(.orange)
                        }
                    }
                    Text(startStation)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Rechts: Großer Countdown
                VStack(spacing: 1) {
                    Text("ABFAHRT IN")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.secondary)

                    let range = departureRange()
                    if let range = range {
                        Text(timerInterval: range, countsDown: true)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(hasDelay ? .orange : .green)
                            .contentTransition(.numericText(countsDown: true))
                    } else {
                        Text("Jetzt")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.green)
                    }
                }
                .frame(width: 100)
            }
            .padding(.horizontal, 12)

            // Ziel-Info unten
            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                Text(endStation)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Text("Ank. \(formattedTime(from: arrivalTimeISO))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .padding(.top, 4)
    }

    // MARK: - During Journey Bottom View (Dynamic Island)

    private var duringJourneyBottomView: some View {
        VStack(spacing: 6) {
            // Station times row
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(formattedTime(from: departureTimeISO))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        if let d = delay, d > 0 {
                            Text("+\(d)'")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundColor(.orange)
                        }
                    }
                    Text(startStation)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Center countdown
                VStack(spacing: 0) {
                    Text("noch")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                    let range = arrivalRange()
                    if let range = range {
                        Text(timerInterval: range, countsDown: true)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(hasDelay ? .orange : accentColor)
                            .contentTransition(.numericText(countsDown: true))
                    } else {
                        Text("--:--")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 64)

                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 3) {
                        if let d = delay, d > 0 {
                            Text("+\(d)'")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        Text(formattedTime(from: arrivalTimeISO))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    Text(endStation)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 12)

            // Umstieg-Indicator (nur wenn weiterer Leg folgt)
            if let transferStop = nextTransferStopName,
               let transferISO = nextTransferArrivalISO {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.orange)
                    Text(transferStop)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let range = transferRange(to: transferISO) {
                        Text(timerInterval: range, countsDown: true)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.orange)
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
                .padding(.horizontal, 12)
            }

            // Progress bar
            JourneyProgressBar(
                departureDate: DateCalculationHelper.parseDate(departureTimeISO) ?? Date(),
                arrivalDate: DateCalculationHelper.parseDate(arrivalTimeISO) ?? Date().addingTimeInterval(1200),
                serviceType: serviceType,
                lineName: lineName,
                delay: delay,
                currentTime: currentTime
            )
            .frame(height: 22)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .padding(.top, 2)
    }

    private func transferRange(to isoString: String) -> ClosedRange<Date>? {
        guard let date = DateCalculationHelper.parseDate(isoString),
              date > currentTime else { return nil }
        return currentTime...date
    }

    private func departureRange() -> ClosedRange<Date>? {
        if let d = delay, d > 0 {
            return DateCalculationHelper.safeCalculateEstimatedDepartureDate(
                from: departureTimeISO, delayMinutes: d, currentTime: currentTime)
        }
        return DateCalculationHelper.safeCalculateDepartureDate(from: departureTimeISO, currentTime: currentTime)
    }

    private func arrivalRange() -> ClosedRange<Date>? {
        if let d = delay, d > 0 {
            return DateCalculationHelper.safeCalculateDelayedArrivalDate(
                from: arrivalTimeISO, delayMinutes: d, currentTime: currentTime)
        }
        return DateCalculationHelper.safeCalculateRealArrivalDate(from: arrivalTimeISO, currentTime: currentTime)
    }

    private func formattedTime(from isoString: String) -> String {
        guard let date = DateCalculationHelper.parseDate(isoString) else { return "--:--" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - Dynamic Island: Compact Leading

struct DynamicIslandCompactLeading: View {
    let serviceType: String
    let lineName: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: StyleHelper.getIcon(for: serviceType, serviceName: lineName))
                .font(.system(size: 11, weight: .bold))
            Text(StyleHelper.getShortName(from: lineName))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundColor(StyleHelper.getColor(for: serviceType, serviceName: lineName))
    }
}

// MARK: - Dynamic Island: Compact Trailing

struct DynamicIslandCompactTrailing: View {
    let departureTimeISO: String
    let arrivalTimeISO: String
    let delay: Int?
    let phase: TripPhase
    let currentTime: Date

    /// Lokal berechnete Phase für sofortigen Übergang
    private var localPhase: LocalPhaseCalculator.LocalPhase {
        if phase == .arrived {
            return .arrived
        }
        return LocalPhaseCalculator.calculate(
            departureTimeISO: departureTimeISO,
            arrivalTimeISO: arrivalTimeISO,
            delay: delay,
            currentTime: currentTime
        )
    }

    var body: some View {
        switch localPhase {
        case .arrived:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.green)
                .frame(width: 40, alignment: .trailing)

        case .beforeDeparture, .duringJourney:
            compactTimer
        }
    }

    @ViewBuilder
    private var compactTimer: some View {
        let hasDelay = (delay ?? 0) > 0
        let isoString = localPhase == .beforeDeparture ? departureTimeISO : arrivalTimeISO
        let range = timerRange(for: isoString)
        let color: Color = {
            if hasDelay { return .orange }
            if localPhase == .beforeDeparture { return .green }
            return .blue
        }()

        if let range = range {
            Text(timerInterval: range, countsDown: true)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(color)
                .contentTransition(.numericText(countsDown: true))
                .frame(width: 44, alignment: .trailing)
        } else {
            Text("--:--")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(color.opacity(0.5))
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func timerRange(for isoString: String) -> ClosedRange<Date>? {
        if let d = delay, d > 0 {
            guard let date = DateCalculationHelper.parseDate(isoString) else { return nil }
            let delayed = date.addingTimeInterval(TimeInterval(d * 60))
            guard delayed > currentTime else { return nil }
            return currentTime...delayed
        }
        guard let date = DateCalculationHelper.parseDate(isoString),
              date > currentTime else { return nil }
        return currentTime...date
    }
}

// MARK: - Dynamic Island: Minimal View

struct DynamicIslandMinimalView: View {
    let departureTimeISO: String
    let serviceType: String
    let lineName: String
    let delay: Int?
    let phase: TripPhase

    var body: some View {
        ZStack {
            if phase == .arrived {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.green)
            } else if let d = delay, d > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.orange)
            } else if phase == .beforeDeparture {
                Image(systemName: "clock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.green)
            } else {
                Image(systemName: StyleHelper.getIcon(for: serviceType, serviceName: lineName))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(StyleHelper.getColor(for: serviceType, serviceName: lineName))
            }
        }
    }
}

// MARK: - Status Badge View (kept for backward compatibility)

struct StatusBadgeView: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(color))
    }
}

// MARK: - Legacy JourneyProgressView (alias)

typealias JourneyProgressView = JourneyProgressBar

// MARK: - Preview Helpers

extension TripLiveActivityAttributes {
    static var previewBeforeDeparture: TripLiveActivityAttributes {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let now = Date()
        let departure = now.addingTimeInterval(180)
        let arrival = departure.addingTimeInterval(20 * 60)

        return TripLiveActivityAttributes(
            tripId: UUID().uuidString,
            startStation: "Mannheim Hbf",
            endStation: "Heidelberg Bismarckplatz",
            totalLegs: 2,
            departureTimeISO: formatter.string(from: departure),
            arrivalTimeISO: formatter.string(from: arrival)
        )
    }

    static var previewDuringJourney: TripLiveActivityAttributes {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let now = Date()
        let departure = now.addingTimeInterval(-300)
        let arrival = now.addingTimeInterval(900)

        return TripLiveActivityAttributes(
            tripId: UUID().uuidString,
            startStation: "Mannheim Hbf",
            endStation: "Heidelberg Bismarckplatz",
            totalLegs: 2,
            departureTimeISO: formatter.string(from: departure),
            arrivalTimeISO: formatter.string(from: arrival)
        )
    }

    static var previewArrived: TripLiveActivityAttributes {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let now = Date()
        let departure = now.addingTimeInterval(-1200)
        let arrival = now.addingTimeInterval(-60)

        return TripLiveActivityAttributes(
            tripId: UUID().uuidString,
            startStation: "Mannheim Hbf",
            endStation: "Heidelberg Bismarckplatz",
            totalLegs: 2,
            departureTimeISO: formatter.string(from: departure),
            arrivalTimeISO: formatter.string(from: arrival)
        )
    }
}

extension TripLiveActivityAttributes.ContentState {
    static var onTime: TripLiveActivityAttributes.ContentState {
        TripLiveActivityAttributes.ContentState(
            currentLegIndex: 0, nextStopName: "Mannheim Paradeplatz", nextStopTime: "14:32",
            estimatedTime: nil, delay: nil, destination: "Heidelberg Bismarckplatz",
            lineName: "Linie 5", serviceType: "STRASSENBAHN", phase: .beforeDeparture
        )
    }

    static var delayed: TripLiveActivityAttributes.ContentState {
        TripLiveActivityAttributes.ContentState(
            currentLegIndex: 0, nextStopName: "Mannheim Paradeplatz", nextStopTime: "14:32",
            estimatedTime: "14:37", delay: 5, destination: "Heidelberg Bismarckplatz",
            lineName: "Linie 5", serviceType: "STRASSENBAHN", phase: .beforeDeparture
        )
    }

    static var duringJourney: TripLiveActivityAttributes.ContentState {
        TripLiveActivityAttributes.ContentState(
            currentLegIndex: 1, nextStopName: "Heidelberg Hbf", nextStopTime: "14:48",
            estimatedTime: nil, delay: nil, destination: "Heidelberg Bismarckplatz",
            lineName: "Linie 5", serviceType: "STRASSENBAHN", phase: .duringJourney
        )
    }

    static var duringJourneyWithTransfer: TripLiveActivityAttributes.ContentState {
        let transferDate = Date().addingTimeInterval(8 * 60)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return TripLiveActivityAttributes.ContentState(
            currentLegIndex: 0, nextStopName: "Heidelberg Hbf", nextStopTime: "14:48",
            estimatedTime: nil, delay: nil, destination: "Heidelberg Bismarckplatz",
            lineName: "Linie 5", serviceType: "STRASSENBAHN", phase: .duringJourney,
            nextTransferStopName: "Heidelberg Hbf",
            nextTransferArrivalISO: fmt.string(from: transferDate)
        )
    }

    static var duringJourneyDelayed: TripLiveActivityAttributes.ContentState {
        TripLiveActivityAttributes.ContentState(
            currentLegIndex: 1, nextStopName: "Heidelberg Hbf", nextStopTime: "14:48",
            estimatedTime: "14:53", delay: 5, destination: "Heidelberg Bismarckplatz",
            lineName: "Linie 5", serviceType: "STRASSENBAHN", phase: .duringJourney
        )
    }

    static var arrived: TripLiveActivityAttributes.ContentState {
        TripLiveActivityAttributes.ContentState(
            currentLegIndex: 2, nextStopName: "Heidelberg Bismarckplatz", nextStopTime: "15:12",
            estimatedTime: nil, delay: nil, destination: "Heidelberg Bismarckplatz",
            lineName: "Linie 5", serviceType: "STRASSENBAHN", phase: .arrived
        )
    }
}
