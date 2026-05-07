import SwiftUI

struct SavedTripsView: View {
    @EnvironmentObject var dataManager: WatchDataManager

    var body: some View {
        if dataManager.savedTrips.isEmpty {
            EmptyTripsView()
        } else {
            List(dataManager.savedTrips) { trip in
                NavigationLink(destination: TripLegListView(trip: trip)) {
                    SavedTripRow(trip: trip)
                }
            }
            .navigationTitle("Geplante Fahrten")
        }
    }
}

// MARK: - Trip-Zeile

private struct SavedTripRow: View {
    let trip: TripData

    private var firstLeg: TripLegData? { trip.legs.first(where: { $0.isTimedLeg }) }
    private var phase: TripPhase { WatchDateHelper.phase(for: trip) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Linie + Abfahrtszeit
            HStack(spacing: 6) {
                if let leg = firstLeg {
                    LineBadgeView(serviceName: leg.serviceName, serviceType: leg.serviceType)
                }
                Spacer()
                HStack(spacing: 3) {
                    Text(WatchDateHelper.formatTime(trip.startTime))
                        .font(.system(.callout, design: .monospaced).bold())
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(WatchDateHelper.formatTime(trip.endTime))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            // Route
            HStack(spacing: 4) {
                Text(trip.startStation)
                    .font(.caption2)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.secondary)
                Text(trip.endStation)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Countdown + Umstiege
            HStack(spacing: 8) {
                PhaseCountdownLabel(trip: trip, phase: phase)

                if trip.interchanges > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 8))
                        Text("\(trip.interchanges)×")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Countdown-Label

private struct PhaseCountdownLabel: View {
    let trip: TripData
    let phase: TripPhase

    var body: some View {
        switch phase {
        case .beforeDeparture:
            if let mins = WatchDateHelper.minutesUntil(trip.startTime) {
                Label(mins == 0 ? "Jetzt" : "in \(mins) Min",
                      systemImage: "clock.fill")
                    .font(.caption2.bold())
                    .foregroundColor(mins <= 2 ? .orange : .cyan)
            }
        case .duringJourney:
            Label("Unterwegs", systemImage: "location.fill")
                .font(.caption2.bold())
                .foregroundColor(.green)
        case .arrived:
            Label("Angekommen", systemImage: "checkmark.circle")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Teilstrecken-Liste

struct TripLegListView: View {
    let trip: TripData

    private var timedLegs: [TripLegData] { trip.legs.filter { $0.isTimedLeg } }

    var body: some View {
        List {
            ForEach(Array(timedLegs.enumerated()), id: \.offset) { _, leg in
                LegRow(leg: leg)
            }
        }
        .navigationTitle(trip.endStation)
    }
}

private struct LegRow: View {
    let leg: TripLegData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LineBadgeView(serviceName: leg.serviceName, serviceType: leg.serviceType)

            HStack(spacing: 4) {
                Text(WatchDateHelper.formatTime(leg.departureTime ?? ""))
                    .font(.system(.caption, design: .monospaced).bold())
                Text(leg.boardStopName ?? "")
                    .font(.caption)
                    .lineLimit(1)
            }

            if let dest = leg.destinationLabel {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Richtung \(dest)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 4) {
                Text(WatchDateHelper.formatTime(leg.arrivalTime ?? ""))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(leg.alightStopName ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Leer-Zustand

private struct EmptyTripsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("Keine Fahrten")
                .font(.headline)
            Text("Plane eine Verbindung in der iPhone-App.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
