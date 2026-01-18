//
//  ContentMediumComponents.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 13.01.26.
//

import SwiftUI
import ActivityKit
import WidgetKit

// ========================================
// MARK: - Helper: Date Calculations
// ========================================

struct DateCalculationHelper {
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    static func isBeforeDeparture(_ departureTimeISO: String, at currentTime: Date) -> Bool {
        guard let departureDate = formatter.date(from: departureTimeISO) else { return false }
        return currentTime < departureDate
    }
    
    static func safeCalculateDepartureDate(from isoString: String, currentTime: Date) -> ClosedRange<Date>? {
        guard let departureDate = formatter.date(from: isoString),
              departureDate > currentTime else { return nil }
        return currentTime...departureDate
    }
    
    static func safeCalculateRealArrivalDate(from arrivalTimeISO: String, currentTime: Date) -> ClosedRange<Date>? {
        guard let arrivalDate = formatter.date(from: arrivalTimeISO),
              arrivalDate > currentTime else { return nil }
        return currentTime...arrivalDate
    }
    
    static func safeCalculateEstimatedDepartureDate(from departureTimeISO: String, delayMinutes: Int, currentTime: Date) -> ClosedRange<Date>? {
        guard let departureDate = formatter.date(from: departureTimeISO) else { return nil }
        let estimatedDepartureDate = departureDate.addingTimeInterval(TimeInterval(delayMinutes * 60))
        guard estimatedDepartureDate > currentTime else { return nil }
        return currentTime...estimatedDepartureDate
    }
    
    static func safeCalculateDelayedArrivalDate(from arrivalTimeISO: String, delayMinutes: Int, currentTime: Date) -> ClosedRange<Date>? {
        guard let arrivalDate = formatter.date(from: arrivalTimeISO) else { return nil }
        let delayedArrivalDate = arrivalDate.addingTimeInterval(TimeInterval(delayMinutes * 60))
        guard delayedArrivalDate > currentTime else { return nil }
        return currentTime...delayedArrivalDate
    }
}

// MARK: - Helper: Styles

struct StyleHelper {
    static func getColor(for serviceType: String) -> Color {
        switch serviceType {
        case "STRASSENBAHN": return .red
        case "BUS": return .blue
        case "S_BAHN": return .green
        default: return .gray
        }
    }
    
    static func getIcon(for serviceType: String) -> String {
        switch serviceType {
        case "STRASSENBAHN": return "tram.fill"
        case "BUS": return "bus.fill"
        case "S_BAHN": return "train.side.front.car"
        default: return "questionmark"
        }
    }
    
    static func getShortName(from serviceName: String) -> String {
        serviceName.replacingOccurrences(of: "RNV ", with: "")
    }
}

// MARK: - Journey Progress View

struct JourneyProgressView: View {
    let departureTimeISO: String
    let arrivalTimeISO: String
    let serviceType: String
    let delay: Int?
    
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0)) { context in
            let departureDate = parseDepartureDate()
            let arrivalDate = parseArrivalDate()
            let currentTime = context.date
            let isBeforeDeparture = currentTime < departureDate
            
            if isBeforeDeparture {
                beforeDepartureView(currentTime: currentTime, departureDate: departureDate)
            } else {
                duringJourneyView(currentTime: currentTime, departureDate: departureDate, arrivalDate: arrivalDate)
            }
        }
    }
    
    @ViewBuilder
    private func beforeDepartureView(currentTime: Date, departureDate: Date) -> some View {
        let actualDepartureDate = (delay != nil && delay! > 0) ?
            departureDate.addingTimeInterval(TimeInterval(delay! * 60)) : departureDate
        
        let totalTimeRemaining = max(0, actualDepartureDate.timeIntervalSince(currentTime))
        let initialTotalTime = actualDepartureDate.timeIntervalSince(Date())
        let progress: CGFloat = initialTotalTime > 0 ?
            min(1.0, max(0.0, 1.0 - (totalTimeRemaining / initialTotalTime))) : 1.0
        
        HStack(spacing: 6) {
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(progress >= 0.2 ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 5, height: 5).animation(.easeInOut, value: progress)
                    Circle().fill(progress >= 0.4 ? Color.blue : Color.gray.opacity(0.5))
                        .frame(width: 5, height: 5).animation(.easeInOut, value: progress)
                    Image(systemName: "figure.run").font(.system(size: 12))
                        .foregroundColor(progress >= 0.6 ? .blue : .gray).animation(.easeInOut, value: progress)
                    Circle().fill(progress >= 0.8 ? Color.blue : Color.gray.opacity(0.5))
                        .frame(width: 5, height: 5).animation(.easeInOut, value: progress)
                    Circle().fill(progress >= 1.0 ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 5, height: 5).animation(.easeInOut, value: progress)
                }
                
                Text(formatTimeRemaining(totalTimeRemaining))
                    .font(.system(size: 12)).fontWeight(.semibold)
                    .foregroundColor(delay != nil && delay! > 0 ? .red : .blue)
                    .monospacedDigit()
            }
            .frame(width: 80).padding(.top, 10)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.3)).frame(height: 15)
                    Capsule().fill(delay != nil && delay! > 0 ? Color.red : Color.blue)
                        .frame(width: geometry.size.width * progress, height: 15)
                        .animation(.easeInOut, value: progress)
                }
            }
            .frame(height: 15).clipShape(Capsule())
        }
    }
    
    @ViewBuilder
    private func duringJourneyView(currentTime: Date, departureDate: Date, arrivalDate: Date) -> some View {
        let progress = calculateJourneyProgress(currentTime: currentTime, departureDate: departureDate, arrivalDate: arrivalDate)
        
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.3))
                    .frame(height: 15)
                
                Capsule().fill(Color.blue)
                    .frame(width: geometry.size.width * progress, height: 15)
                    .animation(.linear(duration: 1.0), value: progress)
                
                HStack {
                    Spacer().frame(width: max(0, geometry.size.width * progress - 12))
                    Image(systemName: StyleHelper.getIcon(for: serviceType))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.blue)
                                .shadow(color: .black.opacity(0.4), radius: 5, x: 0, y: 2)
                        )
                    Spacer()
                }
            }
        }
        .frame(height: 30)
    }
    
    private func parseDepartureDate() -> Date {
        DateCalculationHelper.formatter.date(from: departureTimeISO) ?? Date()
    }
    
    private func parseArrivalDate() -> Date {
        DateCalculationHelper.formatter.date(from: arrivalTimeISO) ?? Date().addingTimeInterval(20 * 60)
    }
    
    private func calculateJourneyProgress(currentTime: Date, departureDate: Date, arrivalDate: Date) -> CGFloat {
        let actualDepartureDate = (delay != nil && delay! > 0) ?
            departureDate.addingTimeInterval(TimeInterval(delay! * 60)) : departureDate
        
        let journeyDuration = arrivalDate.timeIntervalSince(actualDepartureDate)
        let elapsedTime = currentTime.timeIntervalSince(actualDepartureDate)
        
        let progress = min(1.0, max(0.0, elapsedTime / journeyDuration))
        return CGFloat(progress)
    }
    
    private func formatTimeRemaining(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return minutes > 0 ? String(format: "%d:%02d", minutes, seconds) : String(format: "0:%02d", seconds)
    }
}

// MARK: - Status Badge View

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

// MARK: - Angekommen-View

struct ArrivedView: View {
    let context: ActivityViewContext<TripLiveActivityAttributes>
    
    var body: some View {
        VStack(spacing: 16) {
            // Header mit Icon
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.green)
                
                Text("Angekommen!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            // Strecken-Info
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VON")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(context.attributes.startStation)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("NACH")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(context.attributes.endStation)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                // Trennlinie
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 0.5)
                
                // Hinweis
                Text("Schließt automatisch in 1 Minute")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Content Medium View (Lock Screen)

struct ContentMediumView: View {
    let context: ActivityViewContext<TripLiveActivityAttributes>
    let isBeforeDeparture: Bool
    let currentTime: Date
    
    var body: some View {
        if context.state.phase == .arrived {
            ArrivedView(context: context)
        } else {
            regularView
        }
    }
    
    // ✅ GEÄNDERT: Dynamische Höhe je nach Phase
    private var regularView: some View {
        VStack(spacing: 0) {
            headerSection
            progressSection
        }
        .frame(
            minHeight: isBeforeDeparture ? 140 : 120,  //
            maxHeight: isBeforeDeparture ? 180 : 160   //
        )
        .background(Color(.systemBackground))
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(Color.primary)
    }
    
    // ✅ GEÄNDERT: Mehr Padding vor Abfahrt
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                lineInfoBadge
                Spacer()
                statusBadge
            }
            stationInfoRow
        }
        .padding(.horizontal, 14)
        .padding(.top, isBeforeDeparture ? 16 : 24)      // ✅ Mehr Platz oben
        .padding(.bottom, isBeforeDeparture ? 14 : 10)   // ✅ Mehr Platz unten
    }
    
    private var lineInfoBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: StyleHelper.getIcon(for: context.state.serviceType))
                .font(.system(size: 13, weight: .semibold))
            Text(StyleHelper.getShortName(from: context.state.lineName))
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10).fill(StyleHelper.getColor(for: context.state.serviceType)))
    }
    
    private var statusBadge: some View {
        Group {
            if isBeforeDeparture {
                if let delay = context.state.delay, delay > 0 {
                    StatusBadgeView(icon: "clock.badge.exclamationmark", text: "+\(delay)'", color: .red)
                } else {
                    StatusBadgeView(icon: "checkmark.circle.fill", text: "Pünktlich", color: .green)
                }
            } else {
                if let delay = context.state.delay, delay > 0 {

                    HStack(spacing: 3) {
                        Image(systemName: "clock.badge.exclamationmark").font(.system(size: 10))
                        Text("+\(delay) min").font(.system(size: 13, weight: .bold)).lineLimit(1)
                    }
                    .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.red))
                    .frame(width: 110, alignment: .trailing)
                    
                    
                    
                    
                } else {
                    StatusBadgeView(icon: "arrow.right.circle.fill", text: "Unterwegs", color: .blue)
                }
            }
        }
    }
    
    private var stationInfoRow: some View {
        HStack(alignment: .top, spacing: 10) {
            startStationView
            connectionIndicator
            endStationView
        }
    }
    
    private var startStationView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("VON").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
            
            Text(context.attributes.startStation).font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary).lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var connectionIndicator: some View {
        VStack(spacing: 3) {
            Circle().fill(StyleHelper.getColor(for: context.state.serviceType)).frame(width: 5, height: 5)
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1.5).frame(minHeight: 20)
            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
        }
        .frame(width: 30).padding(.top, 14)
    }
    
    private var endStationView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("NACH").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
            
            Text(context.attributes.endStation).font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary).lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    
    
    
    // ✅ GEÄNDERT: Mehr Padding für Progress Section vor Abfahrt
    private var progressSection: some View {
        VStack(spacing: 6) {
            JourneyProgressView(
                departureTimeISO: context.attributes.departureTimeISO,
                arrivalTimeISO: context.attributes.arrivalTimeISO,
                serviceType: context.state.serviceType,
                delay: context.state.delay
            )
            .frame(height: 18)
            
            // Footer nur während der Fahrt anzeigen
            if !isBeforeDeparture {
                footerRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 20)   // ✅ Mehr Platz unten
    }
    
    private var footerRow: some View {
        HStack(spacing: 0) {
            destinationInfo
            Spacer()
            timerDisplay
        }
    }
    
    private var destinationInfo: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(StyleHelper.getColor(for: context.state.serviceType))
            
            Text(context.state.destination)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary).lineLimit(1)
        }
    }
    
    private var timerDisplay: some View {
        HStack(spacing: 3) {
            Image(systemName: "timer")
                .font(.system(size: 9)).foregroundColor(.secondary)
            
            duringJourneyTimer
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.1))
                .padding(.trailing, 110)
        )
    }
    
    @ViewBuilder
    private var duringJourneyTimer: some View {
        if let delay = context.state.delay, delay > 0 {
            let timeRange = DateCalculationHelper.safeCalculateDelayedArrivalDate(
                from: context.attributes.arrivalTimeISO,
                delayMinutes: delay,
                currentTime: currentTime
            )
            
            if let range = timeRange {
                Text(timerInterval: range, countsDown: true)
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.blue)
            } else {
                Text("--:--")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.blue)
            }
        } else {
            let timeRange = DateCalculationHelper.safeCalculateRealArrivalDate(
                from: context.attributes.arrivalTimeISO,
                currentTime: currentTime
            )
            
            if let range = timeRange {
                Text(timerInterval: range, countsDown: true)
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.blue)
            } else {
                Text("--:--")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.blue)
            }
        }
    }
}

// MARK: - Preview Helper Extensions

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
            lineName: "RNV 5", serviceType: "STRASSENBAHN", phase: .beforeDeparture
        )
    }
    
    static var delayed: TripLiveActivityAttributes.ContentState {
        TripLiveActivityAttributes.ContentState(
            currentLegIndex: 0, nextStopName: "Mannheim Paradeplatz", nextStopTime: "14:32",
            estimatedTime: "14:37", delay: 5, destination: "Heidelberg Bismarckplatz",
            lineName: "RNV 5", serviceType: "STRASSENBAHN", phase: .beforeDeparture
        )
    }
    
    static var arrived: TripLiveActivityAttributes.ContentState {
        TripLiveActivityAttributes.ContentState(
            currentLegIndex: 2, nextStopName: "Heidelberg Bismarckplatz", nextStopTime: "15:12",
            estimatedTime: nil, delay: nil, destination: "Heidelberg Bismarckplatz",
            lineName: "RNV 5", serviceType: "STRASSENBAHN", phase: .arrived
        )
    }
}
