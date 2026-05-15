import SwiftUI
import WatchConnectivity

struct DebugView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    DebugStatusRow(label: "Erreichbar",
                                   value: connectivity.isReachable ? "ja" : "nein",
                                   ok: connectivity.isReachable)
                    DebugStatusRow(label: "Credentials",
                                   value: credentialsStatus,
                                   ok: WatchDirectService.shared.hasCredentials)
                    DebugStatusRow(label: "Lädt",
                                   value: connectivity.isLoading ? "ja" : "nein",
                                   ok: !connectivity.isLoading)
                    DebugStatusRow(label: "Abfahrten",
                                   value: "\(connectivity.departures.count)",
                                   ok: !connectivity.departures.isEmpty)
                    if let error = connectivity.lastError {
                        DebugStatusRow(label: "Fehler", value: error, ok: false)
                    }
                }

                Section {
                    Button(action: { connectivity.debugLog.removeAll() }) {
                        Label("Log leeren", systemImage: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section("Log (\(connectivity.debugLog.count))") {
                    if connectivity.debugLog.isEmpty {
                        Text("Kein Log vorhanden")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(connectivity.debugLog.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        }
                    }
                }
            }
            .navigationTitle("Debug")
        }
    }

    private var credentialsStatus: String {
        guard let creds = WatchDirectService.shared.loadCredentials() else { return "keine" }
        if let expiry = creds.tokenExpiry {
            let remaining = Int(expiry - Date().timeIntervalSince1970)
            if remaining > 0 {
                return "Token \(remaining / 60)min"
            } else {
                return "Token abgel."
            }
        }
        return creds.accessToken != nil ? "kein Expiry" : "kein Token"
    }
}

private struct DebugStatusRow: View {
    let label: String
    let value: String
    let ok: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.bold())
                .foregroundColor(ok ? .green : .red)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}
