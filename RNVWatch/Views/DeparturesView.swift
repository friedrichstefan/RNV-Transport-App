import SwiftUI

// Vordefinierte Haltestellen im RNV-Bereich für schnellen Zugriff
private struct QuickStation: Identifiable, Hashable {
    let id: String  // globalID
    let name: String
}

private let quickStations: [QuickStation] = [
    QuickStation(id: "de:08222:115", name: "MA Hauptbahnhof"),
    QuickStation(id: "de:08222:101", name: "MA Paradeplatz"),
    QuickStation(id: "de:08221:1",   name: "HD Hauptbahnhof"),
    QuickStation(id: "de:07311:100", name: "LU Hauptbahnhof"),
    QuickStation(id: "de:08222:110", name: "MA Wasserturm"),
    QuickStation(id: "de:08221:15",  name: "HD Bismarckplatz"),
]

struct DeparturesView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @State private var selectedStationID = quickStations[0].id

    private var selectedStation: QuickStation {
        quickStations.first { $0.id == selectedStationID } ?? quickStations[0]
    }

    var body: some View {
        NavigationStack {
            List {
                // Haltestellenauswahl als Picker (watchOS-nativ)
                Section {
                    Picker("Haltestelle", selection: $selectedStationID) {
                        ForEach(quickStations) { station in
                            Text(station.name).tag(station.id)
                        }
                    }
                    .onChange(of: selectedStationID) { _ in loadDepartures() }
                }

                // Inhaltsbereich
                if connectivity.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let error = connectivity.lastError {
                    ErrorRow(message: error, retry: loadDepartures)
                } else if connectivity.departures.isEmpty {
                    EmptyDeparturesRow(
                        isReachable: connectivity.isReachable,
                        onLoad: loadDepartures
                    )
                } else {
                    ForEach(connectivity.departures) { dep in
                        DepartureRow(departure: dep)
                    }
                }
            }
            .navigationTitle("Abfahrten")
            .onAppear { loadDepartures() }
        }
    }

    private func loadDepartures() {
        connectivity.requestDepartures(
            stationID: selectedStation.id,
            stationName: selectedStation.name
        )
    }
}

// MARK: - Abfahrts-Zeile

private struct DepartureRow: View {
    let departure: WatchDeparture

    private var displayTime: String {
        departure.estimatedTime ?? departure.scheduledTime
    }

    var body: some View {
        HStack(spacing: 6) {
            LineBadgeView(
                serviceName: departure.lineName,
                serviceType: departure.serviceType
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(departure.direction)
                    .font(.caption.bold())
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(WatchDateHelper.formatTime(displayTime))
                        .font(.system(.caption2, design: .monospaced).bold())

                    if let delay = departure.delayMinutes, delay > 0 {
                        Text("+\(delay)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                    } else if let mins = WatchDateHelper.minutesUntil(displayTime) {
                        Text(mins == 0 ? "jetzt" : "in \(mins)'")
                            .font(.caption2)
                            .foregroundColor(mins <= 2 ? .orange : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Leer- und Fehlerzustände

private struct EmptyDeparturesRow: View {
    let isReachable: Bool
    let onLoad: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isReachable ? "tray" : "iphone.slash")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            Text(isReachable ? "Keine Abfahrten" : "iPhone nicht erreichbar")
                .font(.caption.bold())
                .multilineTextAlignment(.center)

            if isReachable {
                Button("Laden", action: onLoad)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }
}

private struct ErrorRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Erneut", action: retry)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}
