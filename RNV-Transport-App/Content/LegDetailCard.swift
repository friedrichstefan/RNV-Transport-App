//
//  LegDetailCard.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//  Redesigned: Zusammenhängende Timeline mit verbesserter Umsteige-Darstellung
//

import SwiftUI

// MARK: - Timed Leg Card (Fahrt mit Verkehrsmittel)

struct TimedLegCard: View {
    let leg: TripLeg
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.colorScheme) private var colorScheme
    private let formatter = DateFormattingHelper.shared

    private var lineColor: Color {
        TransportIconHelper.getLineColor(for: leg.serviceType, serviceName: leg.serviceName)
    }

    private var isSBahn: Bool {
        TransportIconHelper.isSBahnLine(serviceType: leg.serviceType, serviceName: leg.serviceName)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // MARK: Timeline-Leiste links
            timelineColumn
                .frame(width: 44)

            // MARK: Inhalt rechts
            VStack(alignment: .leading, spacing: 14) {
                // Linien-Badge + Richtung
                lineHeaderView

                // Abfahrt
                if let from = leg.boardStopName, let depTime = leg.departureTime {
                    stopRow(
                        stationName: from,
                        scheduledTime: depTime,
                        estimatedTime: leg.estimatedDepartureTime
                    )
                }

                // Fahrtdauer-Indikator
                if let dep = leg.departureTime, let arr = leg.arrivalTime {
                    durationIndicator(dep: dep, arr: arr)
                }

                // Ankunft
                if let to = leg.alightStopName, let arrTime = leg.arrivalTime {
                    stopRow(
                        stationName: to,
                        scheduledTime: arrTime,
                        estimatedTime: leg.estimatedArrivalTime
                    )
                }
            }
            .padding(.vertical, 16)
            .padding(.trailing, 16)
            .padding(.leading, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 6, y: 3)
        )
    }

    // MARK: - Timeline Column

    private var timelineColumn: some View {
        VStack(spacing: 0) {
            // Obere Verbindungslinie (wenn nicht erster Leg)
            if !isFirst {
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 2, height: 12)
            } else {
                Color.clear.frame(width: 2, height: 12)
            }

            // Start-Punkt
            Circle()
                .fill(lineColor)
                .frame(width: 12, height: 12)

            // Verbindungslinie
            Rectangle()
                .fill(lineColor.opacity(0.4))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            // End-Punkt
            Circle()
                .fill(lineColor)
                .frame(width: 12, height: 12)

            // Untere Verbindungslinie (wenn nicht letzter Leg)
            if !isLast {
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 2, height: 12)
            } else {
                Color.clear.frame(width: 2, height: 12)
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Line Header

    private var lineHeaderView: some View {
        HStack(spacing: 10) {
            // Linien-Badge
            HStack(spacing: 5) {
                Image(systemName: TransportIconHelper.getTransportIcon(for: leg.serviceType, serviceName: leg.serviceName))
                    .font(.system(size: isSBahn ? 16 : 11))
                Text(TransportIconHelper.getShortLineName(from: leg.serviceName))
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
            .foregroundColor(isSBahn ? .green : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSBahn
                          ? Color(colorScheme == .dark ? .systemGray5 : .white)
                          : lineColor)
                    .overlay(
                        isSBahn ? Capsule().stroke(Color.green, lineWidth: 1.5) : nil
                    )
            )

            // Richtung
            if let destination = leg.destinationLabel {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                    Text(destination)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Stop Row (Abfahrt / Ankunft)

    @ViewBuilder
    private func stopRow(stationName: String, scheduledTime: String, estimatedTime: String?) -> some View {
        let delayMinutes: Int? = {
            guard let est = estimatedTime else { return nil }
            return formatter.calculateDelay(timetabled: scheduledTime, estimated: est)
        }()
        let hasDelay = (delayMinutes ?? 0) > 0

        HStack(alignment: .top, spacing: 10) {
            // Zeit-Spalte
            VStack(alignment: .trailing, spacing: 2) {
                if hasDelay, let est = estimatedTime {
                    Text(formatter.formatTime(scheduledTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .strikethrough(true, color: .red.opacity(0.6))
                    Text(formatter.formatTime(est))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                } else {
                    Text(formatter.formatTime(scheduledTime))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 48, alignment: .trailing)

            // Station
            VStack(alignment: .leading, spacing: 2) {
                Text(stationName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                // Delay-Badge
                if let d = delayMinutes {
                    if d > 0 {
                        Text("+\(d) Min.")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(d >= 5 ? Color.red : Color.orange))
                    } else {
                        HStack(spacing: 3) {
                            Circle().fill(Color.green).frame(width: 5, height: 5)
                            Text("pünktlich")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                } else if estimatedTime != nil {
                    HStack(spacing: 3) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text("pünktlich")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Duration Indicator

    @ViewBuilder
    private func durationIndicator(dep: String, arr: String) -> some View {
        let duration = formatter.calculateDuration(start: dep, end: arr)

        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text("Fahrzeit: \(duration)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.leading, 58)
    }
}

// MARK: - Transfer Connector (Umstieg / Fußweg)

struct TransferConnector: View {
    let leg: TripLeg
    let previousLeg: TripLeg?
    let nextLeg: TripLeg?

    @Environment(\.colorScheme) private var colorScheme
    private let formatter = DateFormattingHelper.shared

    /// Berechnet die Transfer-Dauer aus den Zeiten der angrenzenden Legs,
    /// da Transfer-/Fußweg-Legs selbst keine Zeiten haben.
    private var transferDuration: String? {
        // Erst eigene Zeiten versuchen (falls vorhanden)
        if let dep = leg.departureTime, let arr = leg.arrivalTime {
            return formatter.calculateDuration(start: dep, end: arr)
        }
        // Sonst aus vorherigem Ankunfts- und nächstem Abfahrts-Zeitpunkt berechnen
        let prevTime = previousLeg?.estimatedArrivalTime ?? previousLeg?.arrivalTime
        let nextTime = nextLeg?.estimatedDepartureTime ?? nextLeg?.departureTime
        if let prev = prevTime, let next = nextTime {
            return formatter.calculateDuration(start: prev, end: next)
        }
        return nil
    }

    private var isWalk: Bool {
        leg.mode == "WALK" || leg.type == .continuousLeg
    }

    var body: some View {
        HStack(spacing: 0) {
            // Timeline-Verbindung
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 44)

            // Transfer-Inhalt
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isWalk ? Color.orange.opacity(0.12) : Color.blue.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: isWalk ? "figure.walk" : "arrow.triangle.swap")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isWalk ? .orange : .blue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(isWalk ? "Fußweg" : "Umstieg")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    if let duration = transferDuration {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(duration)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }

                    // Warnung bei knappem Umstieg
                    if let transferMinutes = getTransferMinutes(), transferMinutes <= 3 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                            Text("Kurzer Umstieg!")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.orange)
                    }
                }

                Spacer()

                // Zeiten kompakt
                if let dep = leg.departureTime, let arr = leg.arrivalTime {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatter.formatTime(dep))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatter.formatTime(arr))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isWalk
                      ? Color.orange.opacity(colorScheme == .dark ? 0.06 : 0.04)
                      : Color.blue.opacity(colorScheme == .dark ? 0.06 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isWalk ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                        )
                )
        )
    }

    private func getTransferMinutes() -> Int? {
        // Eigene Zeiten
        if let dep = leg.departureTime, let arr = leg.arrivalTime,
           let depDate = formatter.parseISO8601(dep),
           let arrDate = formatter.parseISO8601(arr) {
            return Int(arrDate.timeIntervalSince(depDate) / 60)
        }
        // Aus angrenzenden Legs berechnen
        let prevTime = previousLeg?.estimatedArrivalTime ?? previousLeg?.arrivalTime
        let nextTime = nextLeg?.estimatedDepartureTime ?? nextLeg?.departureTime
        if let prev = prevTime, let next = nextTime,
           let prevDate = formatter.parseISO8601(prev),
           let nextDate = formatter.parseISO8601(next) {
            return Int(nextDate.timeIntervalSince(prevDate) / 60)
        }
        return nil
    }
}

// MARK: - Trip Journey View (Gesamte Reise als zusammenhängende Timeline)

struct TripJourneyView: View {
    let legs: [TripLeg]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(legs.enumerated()), id: \.offset) { index, leg in
                let isFirst = index == 0
                let isLast = index == legs.count - 1
                let previousLeg: TripLeg? = index > 0 ? legs[index - 1] : nil
                let nextLeg: TripLeg? = index < legs.count - 1 ? legs[index + 1] : nil

                if leg.isTimedLeg {
                    // Prüfen ob erster/letzter TimedLeg (für Timeline-Enden)
                    let isFirstTimed = legs.prefix(index).allSatisfy { !$0.isTimedLeg }
                    let isLastTimed = legs.suffix(from: index + 1).allSatisfy { !$0.isTimedLeg }

                    TimedLegCard(
                        leg: leg,
                        isFirst: isFirst || isFirstTimed,
                        isLast: isLast || isLastTimed
                    )
                } else {
                    // Fußweg / Umstieg
                    TransferConnector(
                        leg: leg,
                        previousLeg: previousLeg,
                        nextLeg: nextLeg
                    )
                }
            }
        }
    }
}

// MARK: - Trip Route Summary (Kompakte Linien-Übersicht)

struct TripRouteSummary: View {
    let legs: [TripLeg]

    @Environment(\.colorScheme) private var colorScheme
    private let formatter = DateFormattingHelper.shared

    var body: some View {
        let timedLegs = legs.filter { $0.isTimedLeg }
        let walkLegs = legs.filter { !$0.isTimedLeg }

        VStack(alignment: .leading, spacing: 12) {
            // Route-Visualisierung
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(legs.enumerated()), id: \.offset) { index, leg in
                        if leg.isTimedLeg {
                            routeLegPill(leg: leg)
                        } else {
                            routeTransferIndicator(leg: leg)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            // Info-Zeile
            HStack(spacing: 16) {
                if timedLegs.count > 1 {
                    Label("\(timedLegs.count - 1)× umsteigen", systemImage: "arrow.triangle.swap")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !walkLegs.isEmpty {
                    let totalWalkMin = walkLegs.compactMap { leg -> Int? in
                        guard let dep = leg.departureTime, let arr = leg.arrivalTime,
                              let depDate = formatter.parseISO8601(dep),
                              let arrDate = formatter.parseISO8601(arr) else { return nil }
                        return Int(arrDate.timeIntervalSince(depDate) / 60)
                    }.reduce(0, +)

                    if totalWalkMin > 0 {
                        Label("\(totalWalkMin) min Fußweg", systemImage: "figure.walk")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func routeLegPill(leg: TripLeg) -> some View {
        let isSBahn = TransportIconHelper.isSBahnLine(serviceType: leg.serviceType, serviceName: leg.serviceName)
        let lineColor = TransportIconHelper.getLineColor(for: leg.serviceType, serviceName: leg.serviceName)

        HStack(spacing: 4) {
            Image(systemName: TransportIconHelper.getTransportIcon(for: leg.serviceType, serviceName: leg.serviceName))
                .font(.system(size: isSBahn ? 13 : 9))
            Text(TransportIconHelper.getShortLineName(from: leg.serviceName))
                .font(.caption)
                .fontWeight(.bold)
        }
        .foregroundColor(isSBahn ? .green : .white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(isSBahn ? Color(colorScheme == .dark ? .systemGray5 : .white) : lineColor)
                .overlay(isSBahn ? Capsule().stroke(Color.green, lineWidth: 1.5) : nil)
        )
    }

    @ViewBuilder
    private func routeTransferIndicator(leg: TripLeg) -> some View {
        let isWalk = leg.mode == "WALK" || leg.type == .continuousLeg

        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color(.systemGray3))
                    .frame(width: 3, height: 3)
            }
            Image(systemName: isWalk ? "figure.walk" : "arrow.triangle.swap")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color(.systemGray3))
                    .frame(width: 3, height: 3)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Legacy Compatibility Wrapper

struct LegDetailCard: View {
    let leg: TripLeg
    let isLast: Bool

    var body: some View {
        if leg.isTimedLeg {
            TimedLegCard(leg: leg, isFirst: false, isLast: isLast)
        } else {
            TransferConnector(leg: leg, previousLeg: nil, nextLeg: nil)
        }
    }
}