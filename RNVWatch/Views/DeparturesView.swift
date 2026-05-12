import SwiftUI

struct DeparturesView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @State private var selectedStationID   = WatchStation.all[0].id
    @State private var selectedStationName = WatchStation.all[0].name

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: WatchStationPickerView(
                        title: "Haltestelle",
                        stationID: $selectedStationID,
                        stationName: $selectedStationName
                    )) {
                        Label(selectedStationName, systemImage: "tram.fill")
                            .font(.caption)
                    }
                }

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
            .onChange(of: selectedStationID) { loadDepartures() }
            .onChange(of: connectivity.isReachable) { _, isReachable in
                guard isReachable, connectivity.departures.isEmpty, !connectivity.isLoading else { return }
                loadDepartures()
            }
        }
    }

    private func loadDepartures() {
        connectivity.requestDepartures(
            stationID: selectedStationID,
            stationName: selectedStationName
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

#if DEBUG
#Preview("Abfahrten") {
    let conn = WatchConnectivityManager.shared
    conn.departures = WatchDemoData.departures
    return DeparturesView()
        .environmentObject(conn)
}

#Preview("Laden") {
    let conn = WatchConnectivityManager.shared
    conn.isLoading = true
    return DeparturesView()
        .environmentObject(conn)
}

#Preview("Fehler") {
    let conn = WatchConnectivityManager.shared
    conn.lastError = "iPhone nicht erreichbar"
    return DeparturesView()
        .environmentObject(conn)
}
#endif
