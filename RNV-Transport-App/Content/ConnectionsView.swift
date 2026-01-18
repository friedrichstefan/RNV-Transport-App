//
//  ConnectionsView.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 14.01.26.
//

import SwiftUI
import CoreLocation

// MARK: - Main ConnectionsView

struct ConnectionsView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var graphQLService: GraphQLService
    @ObservedObject var locationManager: LocationManager
    
    @State private var selectedStartStation: Station?
    @State private var selectedEndStation: Station?
    @State private var showingStationPicker = false
    @State private var isPickingStartStation = true
    @State private var selectedTrip: DetailedTrip?
    @State private var showingTripDetails = false
    @State private var selectedDateTime: Date = Date()
    @State private var useCustomTime = false
    @State private var scrollOffset: CGFloat = 0
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Header-Größen für Animationen
    private let maxHeaderHeight: CGFloat = 120
    private let minHeaderHeight: CGFloat = 60
    private let scrollThreshold: CGFloat = 80
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color(colorScheme == .dark ? .black : .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Animierter Header
                    RNVScrollableHeaderView(scrollOffset: scrollOffset)
                        .zIndex(1)
                    
                    // Main Content mit ScrollView
                    GeometryReader { geometry in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                // Transparenter Spacer für Header-Platz
                                Color.clear
                                    .frame(height: getCurrentHeaderHeight())
                                
                                // Content Container
                                VStack(spacing: 20) {
                                    if authService.isAuthenticating {
                                        loadingView
                                    } else if authService.isAuthenticated {
                                        mainContent
                                    } else {
                                        manualLoginView
                                    }
                                }
                                .padding(.top, 10)
                            }
                            .background(
                                GeometryReader { scrollGeometry in
                                    Color.clear
                                        .onAppear {
                                            updateScrollOffset(scrollGeometry)
                                        }
                                        .onChange(of: scrollGeometry.frame(in: .global).minY) { _, newValue in
                                            updateScrollOffset(scrollGeometry)
                                        }
                                }
                            )
                        }
                        .coordinateSpace(name: "scroll")
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .sheet(isPresented: $showingStationPicker) {
                StationPickerView(
                    authService: authService,
                    graphQLService: graphQLService,
                    locationManager: locationManager,
                    selectedStation: isPickingStartStation ? $selectedStartStation : $selectedEndStation
                )
            }
            .sheet(isPresented: $showingTripDetails) {
                Group {
                    if let trip = selectedTrip {
                        TripDetailView(trip: trip, authService: authService)
                            .onAppear {
                                print("✅ [DEBUG] TripDetailView Sheet geöffnet für Trip: \(trip.id)")
                            }
                            .onDisappear {
                                print("✅ [DEBUG] TripDetailView Sheet geschlossen")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    selectedTrip = nil
                                }
                            }
                    } else {
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                .scaleEffect(1.5)
                            
                            Text("Verbindung wird geladen...")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Button("Schließen") {
                                showingTripDetails = false
                            }
                            .foregroundColor(.blue)
                            .padding(.top, 20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                    }
                }
            }
        }
    }
    
    // MARK: - Header Height Berechnung
    
    private func getCurrentHeaderHeight() -> CGFloat {
        let progress = min(max(scrollOffset / scrollThreshold, 0), 1)
        return maxHeaderHeight - (progress * (maxHeaderHeight - minHeaderHeight))
    }
    
    private func updateScrollOffset(_ geometry: GeometryProxy) {
        let newOffset = max(0, -geometry.frame(in: .global).minY)
        
        withAnimation(.easeInOut(duration: 0.1)) {
            scrollOffset = newOffset
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)
            
            Text("Anmeldung läuft...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Manual Login View
    
    private var manualLoginView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Anmeldung fehlgeschlagen")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Bitte erneut versuchen")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: {
                Task {
                    await authService.authenticate()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Erneut anmelden")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue)
                )
            }
            .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(spacing: 20) {
            searchCard
            
            if graphQLService.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1.5)
                    .padding()
            }
            
            if !graphQLService.detailedTrips.isEmpty {
                connectionsList
            }
        }
    }
    
    // MARK: - Enhanced Search Card with Date/Time Selection
    
    private var searchCard: some View {
        VStack(spacing: 16) {
            StationSelectButton(
                icon: "circle.fill",
                iconColor: .green,
                title: "Start",
                station: selectedStartStation,
                action: {
                    isPickingStartStation = true
                    showingStationPicker = true
                }
            )
            
            HStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 2, height: 30)
                    .padding(.leading, 19)
                Spacer()
            }
            
            StationSelectButton(
                icon: "location.fill",
                iconColor: .red,
                title: "Ziel",
                station: selectedEndStation,
                action: {
                    isPickingStartStation = false
                    showingStationPicker = true
                }
            )
            
            // Date/Time Selection Section
            VStack(spacing: 12) {
                HStack {
                    Toggle("Geplante Abfahrt", isOn: $useCustomTime)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                
                if useCustomTime {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.clock")
                            .foregroundColor(.blue)
                            .font(.system(size: 20))
                        
                        DatePicker(
                            "Abfahrtszeit",
                            selection: $selectedDateTime,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
            }
            
            if selectedStartStation != nil && selectedEndStation != nil {
                Button(action: {
                    Task {
                        await searchConnections()
                    }
                }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text(useCustomTime ? "Geplante Verbindung suchen" : "Verbindung suchen")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                .padding(.top, 8)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 10, y: 5)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Connections List
    
    private var connectionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verbindungen")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.horizontal)
            
            ForEach(graphQLService.detailedTrips) { trip in
                TripCard(
                    trip: trip,
                    graphQLService: graphQLService,
                    authService: authService
                )
                .onTapGesture {
                    print("🔍 [DEBUG] TripCard getappt für Trip: \(trip.id)")
                    
                    guard !trip.legs.isEmpty else {
                        print("⚠️ [WARNING] Trip hat keine Legs")
                        return
                    }
                    
                    selectedTrip = trip
                    showingTripDetails = true
                    
                    print("✅ [DEBUG] Sheet wird angezeigt")
                }
            }
        }
        .padding(.top, 10)
    }
    
    // MARK: - Helper Functions
    
    private func searchConnections() async {
        let departureTime = useCustomTime ? selectedDateTime : Date()
        
        await graphQLService.getConnections(
            fromGlobalID: selectedStartStation!.globalID,
            toGlobalID: selectedEndStation!.globalID,
            accessToken: authService.accessToken ?? "",
            departureTime: ISO8601DateFormatter().string(from: departureTime)
        )
    }
}

// MARK: - Scrollable Header View

struct RNVScrollableHeaderView: View {
    let scrollOffset: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    private let maxHeaderHeight: CGFloat = 100
    private let minHeaderHeight: CGFloat = 50
    private let scrollThreshold: CGFloat = 80
    
    var body: some View {
        let progress = min(max(scrollOffset / scrollThreshold, 0), 1)
        let currentHeight = maxHeaderHeight - (progress * (maxHeaderHeight - minHeaderHeight))
        let logoSize = 50 - (progress * 20)
        let fontSize = 14 - (progress * 3)
        
        VStack(spacing: 0) {
            ZStack {
                // ✅ Background - KOMPLETT bis zur absoluten Oberkante
                Rectangle()
                    .fill(Color(red: 0/255, green: 43/255, blue: 78/255))
                    .ignoresSafeArea(.all, edges: .all) // ✅ Alle Edges ignorieren
                    .frame(height: currentHeight + 0) // ✅ Extra groß für komplette Abdeckung
                
                // Content - EXTREM hoch positioniert
                VStack(spacing: 0) {
                    // ✅ MINIMALER Spacer - praktisch direkt an der Oberkante
                    Spacer()
                        .frame(height: 30) // ✅ Nur 10px vom Top!
                    
                    HStack(alignment: .center, spacing: max(6, 12 - (progress * 6))) {
                        // Logo Section
                        HStack(spacing: max(4, 8 - (progress * 4))) {
                            Image("rnv-logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: logoSize, height: logoSize)
                                .animation(.easeInOut(duration: 0.3), value: logoSize)
                            
                            if progress < 0.7 {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Rhein-Neckar-Verkehr")
                                        .font(.system(size: fontSize, weight: .semibold))
                                        .foregroundColor(.white)
                                        .opacity(1 - progress)
                                    
                                    Text("Ihre ÖPNV-App")
                                        .font(.system(size: max(6, fontSize - 3), weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .opacity(1 - progress)
                                }
                                .animation(.easeInOut(duration: 0.3), value: progress)
                            }
                        }
                        
                        Spacer()
                        
                        // Time Section
                        VStack(alignment: .trailing, spacing: max(0, 2 - progress)) {
                            TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                                Text(getCurrentTime(timeline.date))
                                    .font(.system(size: max(12, 20 - (progress * 6)),
                                                weight: .bold,
                                                design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            
                            if progress < 0.8 {
                                HStack(spacing: max(2, 4 - (progress * 2))) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: max(3, 6 - (progress * 3)),
                                              height: max(3, 6 - (progress * 3)))
                                        .scaleEffect(1.0)
                                        .animation(
                                            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                            value: UUID()
                                        )
                                    
                                    Text("LIVE • \(getCurrentDate())")
                                        .font(.system(size: max(6, 8 - (progress * 2)), weight: .semibold))
                                        .foregroundColor(.white.opacity(0.9))
                                        .textCase(.uppercase)
                                        .opacity(1 - progress)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, max(8, 14 - (progress * 6)))
                    .padding(.bottom, 15) // ✅ KEIN bottom padding
                    
                    // ✅ Flexibler Spacer um den Rest zu füllen
                    Spacer()
                }
                .frame(maxHeight: currentHeight + 50) // ✅ Maximale Höhe nutzen
            }
            
            // Separator
            LinearGradient(
                colors: [Color.black.opacity(0.1), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 2)
        }
        .frame(height: currentHeight)
        .animation(.easeInOut(duration: 0.3), value: currentHeight)
    }
    
    // MARK: - Helper Functions
    
    private func getCurrentTime(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
    
    private func getCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: Date())
    }
}

// MARK: - Station Select Button (unchanged)

struct StationSelectButton: View {
    let icon: String
    let iconColor: Color
    let title: String
    let station: Station?
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(iconColor.opacity(colorScheme == .dark ? 0.3 : 0.15))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(station?.longName ?? "Haltestelle wählen")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(colorScheme == .dark ? .systemGray5 : .secondarySystemGroupedBackground))
            )
        }
    }
}

#Preview {
    ConnectionsView(
        authService: AuthService(),
        graphQLService: GraphQLService(),
        locationManager: LocationManager()
    )
}
