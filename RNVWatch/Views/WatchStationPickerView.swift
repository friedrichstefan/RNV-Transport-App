import SwiftUI

struct WatchStationPickerView: View {
    let title: String
    @Binding var stationID: String
    @Binding var stationName: String

    @EnvironmentObject var connectivity: WatchConnectivityManager
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if connectivity.stationSearchLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let error = connectivity.stationSearchError, !query.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "iphone.slash")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else if query.isEmpty {
                Text("Haltestelle eingeben...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            } else if connectivity.stationSearchResults.isEmpty {
                Text("Keine Ergebnisse")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(connectivity.stationSearchResults) { station in
                    Button {
                        stationID = station.id
                        stationName = station.name
                        dismiss()
                    } label: {
                        Text(station.name)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle(title)
        .searchable(text: $query, prompt: "Suchen")
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            connectivity.stationSearchResults = []
            connectivity.stationSearchError = nil
            guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                connectivity.requestStationSearch(query: newValue)
            }
        }
        .onDisappear {
            searchTask?.cancel()
            connectivity.stationSearchResults = []
            connectivity.stationSearchLoading = false
        }
    }
}
