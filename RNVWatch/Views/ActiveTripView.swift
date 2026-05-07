import SwiftUI

struct ActiveTripView: View {
    @EnvironmentObject var dataManager: WatchDataManager

    var body: some View {
        if let trip = dataManager.activeTrip {
            TripTrackingView(trip: trip)
        } else {
            NoActiveTripView()
        }
    }
}

// MARK: - Aktive Fahrt vorhanden

private struct TripTrackingView: View {
    let trip: WidgetTripData
    @State private var now = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var phase: TripPhase { WatchDateHelper.phase(for: trip) }
    private var firstLeg: WidgetTripLegData? { trip.legs.first(where: { $0.isTimedLeg }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Linie + Phase
                HStack {
                    if let leg = firstLeg {
                        LineBadgeView(
                            serviceName: leg.serviceName,
                            serviceType: leg.serviceType
                        )
                    }
                    Spacer()
                    PhaseIndicatorView(phase: phase)
                }

                Divider()

                // Abfahrt / Ankunft
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ab")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(WatchDateHelper.formatTime(trip.startTime))
                            .font(.system(.body, design: .monospaced).bold())
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("An")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(WatchDateHelper.formatTime(trip.endTime))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(WatchDateHelper.durationString(start: trip.startTime, end: trip.endTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Countdown / Status
                CountdownView(trip: trip, phase: phase, now: now)

                Divider()

                // Route
                VStack(alignment: .leading, spacing: 4) {
                    RouteStopRow(name: trip.startStation, isStart: true)

                    if trip.interchanges > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(trip.interchanges) Umstieg\(trip.interchanges > 1 ? "e" : "")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 10)
                    }

                    RouteStopRow(name: trip.endStation, isStart: false)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Aktive Fahrt")
        .onReceive(timer) { now = $0 }
    }
}

// MARK: - Countdown / Status Block

private struct CountdownView: View {
    let trip: WidgetTripData
    let phase: TripPhase
    let now: Date

    var body: some View {
        switch phase {
        case .beforeDeparture:
            if let mins = WatchDateHelper.minutesUntil(trip.startTime) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge")
                        .foregroundColor(.cyan)
                    if mins == 0 {
                        Text("Jetzt abfahren")
                            .font(.headline)
                            .foregroundColor(.green)
                    } else {
                        Text("in \(mins) Min")
                            .font(.headline)
                            .foregroundColor(.cyan)
                    }
                }
            }

        case .duringJourney:
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Unterwegs")
                    .font(.headline)
                    .foregroundColor(.green)
                Spacer()
                if let mins = WatchDateHelper.minutesUntil(trip.endTime) {
                    Text("noch \(mins) Min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

        case .arrived:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Angekommen")
                    .font(.headline)
                    .foregroundColor(.green)
            }
        }
    }
}

// MARK: - Keine aktive Fahrt

private struct NoActiveTripView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tram")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text("Keine aktive Fahrt")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Starte die Verfolgung in der iPhone-App.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Wiederverwendbare Subviews

struct LineBadgeView: View {
    let serviceName: String?
    let serviceType: String?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: WatchStyleHelper.icon(serviceType: serviceType, serviceName: serviceName))
                .font(.system(size: 9, weight: .bold))
            Text(WatchStyleHelper.shortName(serviceName))
                .font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(WatchStyleHelper.colorValue(serviceType: serviceType, serviceName: serviceName))
        )
    }
}

private struct PhaseIndicatorView: View {
    let phase: TripPhase

    var body: some View {
        switch phase {
        case .beforeDeparture:
            Label("Bald", systemImage: "clock.fill")
                .font(.caption2.bold())
                .foregroundColor(.cyan)
        case .duringJourney:
            Label("Fährt", systemImage: "location.fill")
                .font(.caption2.bold())
                .foregroundColor(.green)
        case .arrived:
            Label("Da", systemImage: "checkmark.circle.fill")
                .font(.caption2.bold())
                .foregroundColor(.green)
        }
    }
}

private struct RouteStopRow: View {
    let name: String
    let isStart: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isStart ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.caption)
                .foregroundColor(isStart ? .primary : .secondary)
                .lineLimit(1)
        }
    }
}
