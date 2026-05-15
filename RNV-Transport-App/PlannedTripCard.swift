//
//  PlannedTripCard.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 21.01.26.
//

import SwiftUI

struct PlannedTripCard: View {
    let tripId: String
    let onRemove: () -> Void

    @State private var tripData: DetailedTrip?
    @State private var showDetail = false
    @State private var isPulsing = false

    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @Environment(\.colorScheme) private var colorScheme

    private let formatter = DateFormattingHelper.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tappable header area
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Activity")
                        .font(.headline)
                        .fontWeight(.semibold)

                    if let trip = tripData {
                        tripConnectionInfo(trip)
                    } else {
                        Text("Trip ID: \(String(tripId.prefix(8)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                statusBadge
            }
            .contentShape(Rectangle())
            .onTapGesture { showDetail = true }

            HStack(spacing: 12) {
                Button {
                    showDetail = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                        Text("Details")
                            .font(.subheadline)
                    }
                    .foregroundStyle(AppTheme.primaryColor)
                }

                Spacer()

                Button(action: {
                    Task { await handleRemove() }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                        Text("Beenden")
                            .font(.subheadline)
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.surfaceCardAdaptive(colorScheme))
                .shadow(color: AppTheme.shadowColor(), radius: 8, y: 4)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.hairlineAdaptive(colorScheme), lineWidth: 1))
        )
        .onAppear {
            loadTripData()
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
        .sheet(isPresented: $showDetail) {
            if let savedData = TripDataManager.shared.getTripData(for: tripId) {
                PlannedTripDetailSheet(tripId: tripId, tripData: savedData, onEnd: {
                    Task { await handleRemove() }
                })
                .environmentObject(liveActivityManager)
            }
        }
    }

    // MARK: - Line Badge Helper

    @ViewBuilder
    private func lineBadge(serviceType: String?, serviceName: String?, fontSize: Font, iconFontSize: Font, horizontalPadding: CGFloat, verticalPadding: CGFloat, strokeWidth: CGFloat) -> some View {
        let isSBahn = TransportIconHelper.isSBahnLine(serviceType: serviceType, serviceName: serviceName)
        let displayName = TransportIconHelper.getShortLineName(from: serviceName)

        HStack(spacing: fontSize == .caption ? 4 : 2) {
            Image(systemName: TransportIconHelper.getTransportIcon(for: serviceType, serviceName: serviceName))
                .font(isSBahn ? .subheadline : iconFontSize)
            Text(displayName)
                .font(fontSize)
                .fontWeight(.bold)
        }
        .foregroundColor(isSBahn ? .green : .white)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            Group {
                if isSBahn {
                    Capsule()
                        .fill(Color.white)
                        .overlay(Capsule().stroke(Color.green, lineWidth: strokeWidth))
                } else {
                    Capsule()
                        .fill(TransportIconHelper.getLineColor(for: serviceType, serviceName: serviceName))
                }
            }
        )
    }

    // MARK: - Trip Connection Info

    @ViewBuilder
    private func tripConnectionInfo(_ trip: DetailedTrip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(formatter.formatTime(trip.startTime))
                    .font(.headline)
                    .fontWeight(.bold)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(formatter.formatTime(trip.endTime))
                    .font(.headline)
                    .fontWeight(.bold)
            }

            if let firstTimedLeg = trip.legs.first(where: { $0.isTimedLeg }),
               firstTimedLeg.serviceName != nil,
               let destination = firstTimedLeg.destinationLabel {

                HStack(spacing: 8) {
                    lineBadge(
                        serviceType: firstTimedLeg.serviceType,
                        serviceName: firstTimedLeg.serviceName,
                        fontSize: .caption,
                        iconFontSize: .caption2,
                        horizontalPadding: 8,
                        verticalPadding: 4,
                        strokeWidth: 1.5
                    )

                    Text("→ \(destination)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 16, height: 16)
                    .scaleEffect(isPulsing ? 1.6 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }

            Text("Aktiv")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.green.opacity(0.12))
        )
    }

    // MARK: - Actions

    private func loadTripData() {
        if let savedTrip = TripDataManager.shared.getTripData(for: tripId) {
            self.tripData = DetailedTrip(
                startTime: savedTrip.startTime,
                endTime: savedTrip.endTime,
                interchanges: savedTrip.interchanges,
                legs: savedTrip.legs.map { legData in
                    let legType = legData.legType.flatMap { LegType(rawValue: $0) } ?? .timedLeg
                    return TripLeg(
                        type: legType,
                        mode: nil,
                        boardStopName: legData.boardStopName,
                        alightStopName: legData.alightStopName,
                        departureTime: legData.departureTime,
                        arrivalTime: legData.arrivalTime,
                        estimatedDepartureTime: nil,
                        estimatedArrivalTime: nil,
                        serviceType: legData.serviceType,
                        serviceName: legData.serviceName,
                        serviceDescription: nil,
                        destinationLabel: legData.destinationLabel
                    )
                }
            )
        }
    }

    private func handleRemove() async {
        await liveActivityManager.endActivity(tripId: tripId)
        LiveActivityState.shared.setTripActive(tripId, isActive: false)
        TripDataManager.shared.archiveAndRemoveTripData(for: tripId)
        onRemove()
    }
}
