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

    @State private var tripStatus: String = "Aktiv"
    @State private var isExpanded = false
    @State private var tripData: DetailedTrip?

    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @Environment(\.colorScheme) private var colorScheme

    private let formatter = DateFormattingHelper.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            if let trip = tripData, isExpanded {
                tripDetailsSection(trip)
                    .transition(.opacity.combined(with: .scale))
            }

            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                        Text(isExpanded ? "Weniger" : "Details")
                            .font(.subheadline)
                    }
                    .foregroundStyle(AppTheme.primaryColor)
                }

                Spacer()

                Button(action: {
                    Task {
                        await handleRemove()
                    }
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
                .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, y: 4)
        )
        .onAppear {
            loadTripData()
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
               let serviceName = firstTimedLeg.serviceName,
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
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)

            Text(tripStatus)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.green.opacity(0.15))
        )
    }

    // MARK: - Trip Details Section

    @ViewBuilder
    private func tripDetailsSection(_ trip: DetailedTrip) -> some View {
        VStack(spacing: 8) {
            Divider()

            HStack {
                Text("Umsteige:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(trip.interchanges == 0 ? "Direkte Verbindung" : "\(trip.interchanges) Umstieg\(trip.interchanges == 1 ? "" : "e")")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            HStack {
                Text("Fahrzeit:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatter.calculateDuration(start: trip.startTime, end: trip.endTime))
                    .font(.caption)
                    .fontWeight(.medium)
            }

            if trip.legs.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Linien:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 6) {
                        ForEach(trip.legs.filter { $0.isTimedLeg }, id: \.id) { leg in
                            if leg.serviceName != nil {
                                lineBadge(
                                    serviceType: leg.serviceType,
                                    serviceName: leg.serviceName,
                                    fontSize: .system(size: 8, weight: .bold),
                                    iconFontSize: .system(size: 8),
                                    horizontalPadding: 4,
                                    verticalPadding: 2,
                                    strokeWidth: 1
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
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
            #if DEBUG
            print("✅ [PLANNED] Trip-Daten geladen für: \(String(tripId.prefix(8)))")
            #endif
        }
    }

    private func handleRemove() async {
        #if DEBUG
        print("🛑 [PLANNED] Beende Live Activity für Trip: \(String(tripId.prefix(8)))")
        #endif

        await liveActivityManager.endActivity(tripId: tripId)
        LiveActivityState.shared.setTripActive(tripId, isActive: false)
        TripDataManager.shared.removeTripData(for: tripId)

        onRemove()

        #if DEBUG
        print("✅ [PLANNED] Komplett bereinigt: Live Activity, State und Daten")
        #endif
    }
}
