//
//  LegDetailCard.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 18.01.26.
//

import SwiftUI

// MARK: - Leg Detail Card

struct LegDetailCard: View {
    let leg: TripLeg
    let isLast: Bool
    
    @State private var isExpanded = false
    @State private var showingIntermediateStations = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 4) {
                    Circle()
                        .fill(leg.type == "TimedLeg" ? getLineColor(for: leg.serviceType) : Color(.systemGray4))
                        .frame(width: 12, height: 12)
                    
                    if !isLast {
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: 2, height: isExpanded ? 120 : 60)
                            .animation(.easeInOut(duration: 0.3), value: isExpanded)
                    }
                }
                .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 12) {
                    if leg.type == "TimedLeg" {
                        // Transport line badge
                        HStack(spacing: 8) {
                            Image(systemName: getTransportIcon(for: leg.serviceType))
                                .font(.caption)
                            Text(getShortLineName(from: leg.serviceName))
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(getLineColor(for: leg.serviceType)))
                        
                        // Destination
                        if let destination = leg.destinationLabel {
                            HStack {
                                Image(systemName: "arrow.forward")
                                    .font(.caption2)
                                Text(destination)
                                    .font(.subheadline)
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        // Main journey information with expand button
                        VStack(alignment: .leading, spacing: 8) {
                            // Departure and arrival info
                            journeyMainInfo
                            
                            // Expand/Collapse button for intermediate stations
                            if hasIntermediateStations {
                                expandButton
                            }
                            
                            // Expandable intermediate stations
                            if isExpanded && hasIntermediateStations {
                                intermediateStationsView
                            }
                        }
                    } else {
                        // Walking/Transfer leg
                        HStack(spacing: 8) {
                            Image(systemName: leg.mode == "WALK" ? "figure.walk" : "arrow.right")
                                .font(.title3)
                            Text(leg.serviceName ?? leg.mode ?? "")
                                .font(.headline)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 5, y: 2)
            )
        }
    }
    
    // MARK: - Main Journey Info
    
    @ViewBuilder
    private var journeyMainInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Departure
            if let from = leg.boardStopName, let depTime = leg.departureTime {
                departureInfoView(from: from, depTime: depTime)
            }
            
            // Arrival
            if let to = leg.alightStopName, let arrTime = leg.arrivalTime {
                arrivalInfoView(to: to, arrTime: arrTime)
            }
        }
    }
    
    // MARK: - Expand Button
    
    @ViewBuilder
    private var expandButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                
                Text(isExpanded ? "Weniger anzeigen" : "\(getIntermediateStationsCount()) Zwischenstationen")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Intermediate Stations View
    
    @ViewBuilder
    private var intermediateStationsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zwischenstationen")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(getIntermediateStations(), id: \.self) { station in
                    intermediateStationRow(station: station)
                }
            }
            .padding(.leading, 16)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(colorScheme == .dark ? .systemGray5 : .secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Intermediate Station Row
    
    @ViewBuilder
    private func intermediateStationRow(station: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(getLineColor(for: leg.serviceType).opacity(0.6))
                .frame(width: 6, height: 6)
            
            Text(station)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Geschätzte Zeit (simuliert)
            Text(generateEstimatedTime(for: station))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                )
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Helper Properties & Functions
    
    private var hasIntermediateStations: Bool {
        return leg.type == "TimedLeg" && leg.boardStopName != nil && leg.alightStopName != nil
    }
    
    private func getIntermediateStationsCount() -> Int {
        return getIntermediateStations().count
    }
    
    // Simulierte Zwischenstationen (da API keine liefert)
    private func getIntermediateStations() -> [String] {
        guard let serviceType = leg.serviceType,
              let boardStop = leg.boardStopName,
              let alightStop = leg.alightStopName else {
            return []
        }
        
        // Simulierte Zwischenstationen basierend auf Verkehrsmittel und Route
        switch serviceType {
        case "STRASSENBAHN":
            return generateTramStations(from: boardStop, to: alightStop)
        case "BUS":
            return generateBusStations(from: boardStop, to: alightStop)
        case "S_BAHN":
            return generateSBahnStations(from: boardStop, to: alightStop)
        default:
            return []
        }
    }
    
    // Simulierte Stationen-Generierung
    private func generateTramStations(from start: String, to end: String) -> [String] {
        let commonTramStops = [
            "Paradeplatz", "Wasserturm", "Rosengarten", "Neckarstadt West",
            "Universitätsklinikum", "Neuostheim", "Feudenheim", "Käfertal"
        ]
        
        return Array(commonTramStops.shuffled().prefix(Int.random(in: 2...4)))
    }
    
    private func generateBusStations(from start: String, to end: String) -> [String] {
        let commonBusStops = [
            "Hauptbahnhof", "Marktplatz", "Stadthaus", "Planken",
            "Schloss", "Bismarckplatz", "Neuenheimer Feld", "Handschuhsheim"
        ]
        
        return Array(commonBusStops.shuffled().prefix(Int.random(in: 3...5)))
    }
    
    private func generateSBahnStations(from start: String, to end: String) -> [String] {
        let commonSBahnStops = [
            "Mannheim Hbf", "Mannheim-Neckarstadt", "Heidelberg-Pfaffengrund",
            "Heidelberg Altstadt", "Heidelberg Hbf", "Weinheim", "Ladenburg"
        ]
        
        return Array(commonSBahnStops.shuffled().prefix(Int.random(in: 1...3)))
    }
    
    // Geschätzte Ankunftszeiten generieren
    private func generateEstimatedTime(for station: String) -> String {
        let baseMinutes = Int.random(in: 2...8)
        
        if let depTime = leg.departureTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            if let depDate = formatter.date(from: depTime) {
                let estimatedDate = depDate.addingTimeInterval(TimeInterval(baseMinutes * 60))
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"
                timeFormatter.timeZone = .current
                return timeFormatter.string(from: estimatedDate)
            }
        }
        
        return "~\(baseMinutes) Min"
    }
    
    // MARK: - Departure/Arrival Info Views
    
    @ViewBuilder
    private func departureInfoView(from: String, depTime: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if let estimatedTime = leg.estimatedDepartureTime {
                    let delay = calculateDelay(timetabled: depTime, estimated: estimatedTime)
                    if delay > 0 {
                        Text(formatTime(depTime))
                            .font(.headline)
                            .strikethrough(true, color: .red)
                            .foregroundColor(.secondary)
                        
                        Text(formatTime(estimatedTime))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                        
                        Text("+\(delay) min")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    } else {
                        Text(formatTime(depTime))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                } else {
                    Text(formatTime(depTime))
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Text(from)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func arrivalInfoView(to: String, arrTime: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if let estimatedTime = leg.estimatedArrivalTime {
                    let delay = calculateDelay(timetabled: arrTime, estimated: estimatedTime)
                    if delay > 0 {
                        Text(formatTime(arrTime))
                            .font(.headline)
                            .strikethrough(true, color: .red)
                            .foregroundColor(.secondary)
                        
                        Text(formatTime(estimatedTime))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                        
                        Text("+\(delay) min")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    } else {
                        Text(formatTime(arrTime))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                } else {
                    Text(formatTime(arrTime))
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Text(to)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: isoString) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            timeFormatter.timeZone = TimeZone.current
            return timeFormatter.string(from: date)
        }
        return isoString
    }
    
    private func calculateDelay(timetabled: String, estimated: String) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let timetabledDate = formatter.date(from: timetabled),
              let estimatedDate = formatter.date(from: estimated) else {
            return 0
        }
        
        let delaySeconds = estimatedDate.timeIntervalSince(timetabledDate)
        return max(0, Int(delaySeconds / 60))
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
