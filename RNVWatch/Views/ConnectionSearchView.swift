import SwiftUI

struct ConnectionSearchView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @State private var fromID   = WatchStation.all[0].id
    @State private var fromName = WatchStation.all[0].name
    @State private var toID     = WatchStation.all[1].id
    @State private var toName   = WatchStation.all[1].name

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: WatchStationPickerView(
                        title: "Von",
                        stationID: $fromID,
                        stationName: $fromName
                    )) {
                        LabeledStationRow(label: "Von", name: fromName)
                    }

                    NavigationLink(destination: WatchStationPickerView(
                        title: "Nach",
                        stationID: $toID,
                        stationName: $toName
                    )) {
                        LabeledStationRow(label: "Nach", name: toName)
                    }
                }

                Section {
                    Button(action: search) {
                        HStack {
                            Spacer()
                            Label("Suchen", systemImage: "magnifyingglass")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(fromID == toID || connectivity.connectionsLoading)
                }

                if connectivity.connectionsLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if let error = connectivity.connectionsError {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(error).font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button("Erneut", action: search).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(connectivity.connectionResults) { trip in
                        NavigationLink(destination: WatchTripDetailView(trip: trip)) {
                            ConnectionResultRow(trip: trip)
                        }
                    }
                }
            }
            .navigationTitle("Verbindungen")
        }
    }

    private func search() {
        connectivity.requestConnections(
            fromID: fromID, toID: toID,
            fromName: fromName, toName: toName
        )
    }
}

// MARK: - Haltestellen-Zeile

private struct LabeledStationRow: View {
    let label: String
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(name)
                .font(.caption)
                .lineLimit(1)
        }
    }
}

// MARK: - Ergebnis-Zeile

private struct ConnectionResultRow: View {
    let trip: TripData

    private var firstLeg: TripLegData? { trip.legs.first(where: { $0.isTimedLeg }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let leg = firstLeg {
                    LineBadgeView(serviceName: leg.serviceName, serviceType: leg.serviceType)
                }
                Spacer()
                if trip.interchanges > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 8))
                        Text("\(trip.interchanges)×").font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 3) {
                Text(WatchDateHelper.formatTime(trip.startTime))
                    .font(.system(.callout, design: .monospaced).bold())
                Image(systemName: "arrow.right").font(.caption2).foregroundColor(.secondary)
                Text(WatchDateHelper.formatTime(trip.endTime))
                    .font(.system(.callout, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
                Text(WatchDateHelper.durationString(start: trip.startTime, end: trip.endTime))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Trip-Detail (Legs)

struct WatchTripDetailView: View {
    let trip: TripData

    private var timedLegs: [TripLegData] { trip.legs.filter { $0.isTimedLeg } }

    var body: some View {
        List {
            ForEach(Array(timedLegs.enumerated()), id: \.offset) { _, leg in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        LineBadgeView(serviceName: leg.serviceName, serviceType: leg.serviceType)
                        if let dest = leg.destinationLabel {
                            Text("→ \(dest)").font(.caption2).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(WatchDateHelper.formatTime(leg.departureTime ?? ""))
                            .font(.system(.footnote, design: .monospaced).bold())
                        Text(leg.boardStopName ?? "").font(.footnote).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(WatchDateHelper.formatTime(leg.arrivalTime ?? ""))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(leg.alightStopName ?? "").font(.footnote).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("\(trip.startStation) → \(trip.endStation)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
