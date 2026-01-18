//
//  PlannedTripsView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import SwiftUI

struct PlannedTripsView: View {
    @StateObject private var liveActivityManager = LiveActivityManager()
    @State private var activeTrips: [String] = []
    @State private var refreshTimer: Timer?
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .systemGroupedBackground)
                    .ignoresSafeArea()
                
                if activeTrips.isEmpty {
                    emptyStateView
                } else {
                    activeTripsList
                }
            }
            .navigationTitle("Geplante Fahrten")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshActiveTrips) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                }
                
                if !activeTrips.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: endAllTrips) {
                            Text("Alle beenden")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .onAppear {
            refreshActiveTrips()
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Keine aktiven Fahrten")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text("Live Activities werden hier angezeigt, sobald du eine Verbindung verfolgst")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                // Navigation zur Hauptseite
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    if let tabView = window.rootViewController as? UITabBarController {
                        tabView.selectedIndex = 0 // Zurück zu Verbindungen
                    }
                }
            }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Verbindung suchen")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue)
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
        }
    }
    
    // MARK: - Active Trips List
    
    private var activeTripsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(activeTrips, id: \.self) { tripId in
                    PlannedTripCard(
                        tripId: tripId,
                        onRemove: {
                            removeTrip(tripId)
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helper Functions
    
    private func refreshActiveTrips() {
        activeTrips = LiveActivityState.shared.getAllActiveTrips()
    }
    
    private func removeTrip(_ tripId: String) {
        Task {
            await liveActivityManager.endActivity(tripId: tripId)
            await MainActor.run {
                activeTrips.removeAll { $0 == tripId }
            }
        }
    }
    
    private func endAllTrips() {
        Task {
            await liveActivityManager.endAllActivitiesAndResetToggles()
            await MainActor.run {
                activeTrips.removeAll()
            }
        }
    }
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            refreshActiveTrips()
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Planned Trip Card

struct PlannedTripCard: View {
    let tripId: String
    let onRemove: () -> Void
    
    @State private var tripStatus: String = "Aktiv"
    @State private var isExpanded = false
    @State private var tripData: DetailedTrip? // ✅ NEU: Echte Trip-Daten
    
    @StateObject private var liveActivityManager = LiveActivityManager()
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Activity")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    // ✅ Zeige echte Verbindungsdaten wenn verfügbar
                    if let trip = tripData {
                        tripConnectionInfo(trip)
                    } else {
                        Text("Trip ID: \(String(tripId.prefix(8)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Status Badge
                statusBadge
            }
            
            // ✅ Verbindungsdetails wenn verfügbar
            if let trip = tripData, isExpanded {
                tripDetailsSection(trip)
                    .transition(.opacity.combined(with: .scale))
            }
            
            // Control Buttons
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
                    .foregroundColor(.blue)
                }
                
                Spacer()
                
                // ✅ Verbesserter Beenden-Button
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
    
    // MARK: - Trip Connection Info
    
    @ViewBuilder
    private func tripConnectionInfo(_ trip: DetailedTrip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Hauptverbindung
            HStack(spacing: 8) {
                Text(formatTime(trip.startTime))
                    .font(.headline)
                    .fontWeight(.bold)
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(formatTime(trip.endTime))
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            // Erste Linie anzeigen
            if let firstTimedLeg = trip.legs.first(where: { $0.type == "TimedLeg" }),
               let serviceName = firstTimedLeg.serviceName,
               let destination = firstTimedLeg.destinationLabel {
                
                HStack(spacing: 8) {
                    // Linien-Badge
                    HStack(spacing: 4) {
                        Image(systemName: getTransportIcon(for: firstTimedLeg.serviceType))
                            .font(.caption2)
                        Text(getShortLineName(from: serviceName))
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(getLineColor(for: firstTimedLeg.serviceType)))
                    
                    // Richtung
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
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: UUID())
            
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
            
            // Umstiegsinformationen
            HStack {
                Text("Umsteige:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(trip.interchanges == 0 ? "Direkte Verbindung" : "\(trip.interchanges) Umstieg\(trip.interchanges == 1 ? "" : "e")")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            // Dauer
            HStack {
                Text("Fahrzeit:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(calculateDuration(start: trip.startTime, end: trip.endTime))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            // Alle Linien anzeigen
            if trip.legs.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Linien:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        ForEach(trip.legs.filter { $0.type == "TimedLeg" }) { leg in
                            if let serviceName = leg.serviceName {
                                HStack(spacing: 2) {
                                    Image(systemName: getTransportIcon(for: leg.serviceType))
                                        .font(.system(size: 8))
                                    Text(getShortLineName(from: serviceName))
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(getLineColor(for: leg.serviceType)))
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
        // ✅ Echte Trip-Daten laden
        if let savedTrip = TripDataManager.shared.getTripData(for: tripId) {
            // Konvertiere TripData zurück zu DetailedTrip für UI
            self.tripData = DetailedTrip(
                startTime: savedTrip.startTime,
                endTime: savedTrip.endTime,
                interchanges: savedTrip.interchanges,
                legs: savedTrip.legs.map { legData in
                    TripLeg(
                        type: "TimedLeg",
                        mode: nil,
                        boardStopName: savedTrip.startStation,
                        alightStopName: savedTrip.endStation,
                        departureTime: savedTrip.startTime,
                        arrivalTime: savedTrip.endTime,
                        estimatedDepartureTime: nil,
                        estimatedArrivalTime: nil,
                        serviceType: legData.serviceType,
                        serviceName: legData.serviceName,
                        serviceDescription: nil,
                        destinationLabel: legData.destinationLabel
                    )
                }
            )
            print("✅ [PLANNED] Trip-Daten geladen für: \(tripId)")
        }
    }
    
    private func handleRemove() async {
        print("🛑 [PLANNED] Beende Live Activity für Trip: \(tripId)")
        
        // ✅ 1. Live Activity beenden
        await liveActivityManager.endActivity(tripId: tripId)
        
        // ✅ 2. Toggle-State zurücksetzen
        LiveActivityState.shared.setTripActive(tripId, isActive: false)
        
        // ✅ 3. Gespeicherte Trip-Daten entfernen
        TripDataManager.shared.removeTripData(for: tripId)
        
        // ✅ 4. UI-Update
        onRemove()
        
        print("✅ [PLANNED] Komplett bereinigt: Live Activity, State und Daten")
    }
    
    // MARK: - Helper Functions
    
    private func formatTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: isoString) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            timeFormatter.timeZone = .current
            return timeFormatter.string(from: date)
        }
        return isoString.prefix(5).description // Fallback
    }
    
    private func calculateDuration(start: String, end: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let startDate = formatter.date(from: start),
              let endDate = formatter.date(from: end) else { return "?" }
        
        let duration = endDate.timeIntervalSince(startDate)
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
    
    private func getLineColor(for serviceType: String?) -> Color {
        switch serviceType {
        case "STRASSENBAHN": return .red
        case "BUS": return .blue
        case "S_BAHN": return .green
        default: return .gray
        }
    }
    
    private func getShortLineName(from serviceName: String?) -> String {
        guard let name = serviceName else { return "?" }
        return name.replacingOccurrences(of: "RNV ", with: "")
    }
    
    private func getTransportIcon(for serviceType: String?) -> String {
        switch serviceType {
        case "STRASSENBAHN": return "tram.fill"
        case "BUS": return "bus.fill"
        case "S_BAHN": return "train.side.front.car"
        default: return "questionmark"
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    PlannedTripsView()
}
