//
//  LegDetailCard.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import SwiftUI

struct LegDetailCard: View {
    let leg: TripLeg
    let isLast: Bool

    @State private var isExpanded = false

    @Environment(\.colorScheme) private var colorScheme

    private let formatter = DateFormattingHelper.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 4) {
                    Circle()
                        .fill(leg.isTimedLeg ? TransportIconHelper.getLineColor(for: leg.serviceType) : Color(.systemGray4))
                        .frame(width: 12, height: 12)

                    if !isLast {
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: 2, height: isExpanded ? 120 : 60)
                            .animation(.easeInOut(duration: 0.3), value: isExpanded)
                    }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 12) {
                    if leg.isTimedLeg {
                        // Transport line badge
                        HStack(spacing: 8) {
                            Image(systemName: TransportIconHelper.getTransportIcon(for: leg.serviceType))
                                .font(.caption)
                            Text(TransportIconHelper.getShortLineName(from: leg.serviceName))
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(TransportIconHelper.getLineColor(for: leg.serviceType)))

                        // Destination
                        if let destination = leg.destinationLabel {
                            HStack {
                                Image(systemName: "arrow.forward")
                                    .font(.caption2)
                                Text(destination)
                                    .font(.subheadline)
                            }
                            .foregroundColor(.secondary)
                        }

                        // Main journey information
                        VStack(alignment: .leading, spacing: 8) {
                            journeyMainInfo
                        }
                    } else {
                        // Walking/Transfer leg
                        HStack(spacing: 8) {
                            Image(systemName: leg.mode == "WALK" ? "figure.walk" : "arrow.right")
                                .font(.title3)
                            Text(leg.serviceName ?? leg.mode ?? "")
                                .font(.headline)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 5, y: 2)
            )
        }
    }

    // MARK: - Main Journey Info

    @ViewBuilder
    private var journeyMainInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let from = leg.boardStopName, let depTime = leg.departureTime {
                departureInfoView(from: from, depTime: depTime)
            }

            if let to = leg.alightStopName, let arrTime = leg.arrivalTime {
                arrivalInfoView(to: to, arrTime: arrTime)
            }
        }
    }

    // MARK: - Departure/Arrival Info Views

    @ViewBuilder
    private func departureInfoView(from: String, depTime: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if let estimatedTime = leg.estimatedDepartureTime {
                    let delay = formatter.calculateDelay(timetabled: depTime, estimated: estimatedTime)
                    if let delay = delay, delay > 0 {
                        Text(formatter.formatTime(depTime))
                            .font(.headline)
                            .strikethrough(true, color: .red)
                            .foregroundColor(.secondary)

                        Text(formatter.formatTime(estimatedTime))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.red)

                        Text("+\(delay) min")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    } else {
                        Text(formatter.formatTime(depTime))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                } else {
                    Text(formatter.formatTime(depTime))
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Text(from)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func arrivalInfoView(to: String, arrTime: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if let estimatedTime = leg.estimatedArrivalTime {
                    let delay = formatter.calculateDelay(timetabled: arrTime, estimated: estimatedTime)
                    if let delay = delay, delay > 0 {
                        Text(formatter.formatTime(arrTime))
                            .font(.headline)
                            .strikethrough(true, color: .red)
                            .foregroundColor(.secondary)

                        Text(formatter.formatTime(estimatedTime))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.red)

                        Text("+\(delay) min")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    } else {
                        Text(formatter.formatTime(arrTime))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                } else {
                    Text(formatter.formatTime(arrTime))
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Text(to)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
