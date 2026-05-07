//
//  TransitMapSheet.swift
//  RNV-Transport-App
//

import SwiftUI
import MapKit
import Combine

// MARK: - ViewModel

@MainActor
final class TransitMapViewModel: ObservableObject {
    @Published var originItem: MKMapItem?
    @Published var destinationItem: MKMapItem?
    @Published var route: MKRoute?
    @Published var stopItems: [MKMapItem] = []
    @Published var transferItems: [MKMapItem] = []
    @Published var transitPolylines: [MKPolyline] = []
    @Published var isLoading = true
    @Published var routeUnavailable = false

    nonisolated private static let rnvRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.4875, longitude: 8.4660),
        latitudinalMeters: 80_000,
        longitudinalMeters: 80_000
    )

    func loadRoute(from originName: String, to destinationName: String) async {
        isLoading = true
        routeUnavailable = false
        transferItems = []
        do {
            let o = try await findStop(qualifiedName(originName))
            let d = try await findStop(qualifiedName(destinationName))
            originItem = o
            destinationItem = d
            stopItems = [o, d]

            let req = MKDirections.Request()
            req.source = o
            req.destination = d
            req.transportType = .transit
            let resp = try await MKDirections(request: req).calculate()
            if let r = resp.routes.first {
                route = r
                transitPolylines = r.steps
                    .filter { $0.transportType != .walking }
                    .map { $0.polyline }
            }
        } catch {
            routeUnavailable = route == nil
        }
        isLoading = false
    }

    func loadStops(legs: [TripLeg]) async {
        isLoading = true
        routeUnavailable = false
        stopItems = []
        transferItems = []
        transitPolylines = []
        route = nil

        // Build ordered stop list: board → intermediates → alight per timed leg
        struct StopEntry {
            let index: Int
            let name: String
            let isLegBoundary: Bool
            let coordinate: CLLocationCoordinate2D?  // nil = needs geocoding
        }
        var entries: [StopEntry] = []
        for leg in legs where leg.isTimedLeg {
            if let board = leg.boardStopName, entries.last?.name != board {
                let coord: CLLocationCoordinate2D? = (leg.boardLatitude != nil && leg.boardLongitude != nil)
                    ? CLLocationCoordinate2D(latitude: leg.boardLatitude!, longitude: leg.boardLongitude!)
                    : nil
                entries.append(.init(index: entries.count, name: board, isLegBoundary: true, coordinate: coord))
            }
            for stop in leg.intermediateStops where entries.last?.name != stop.name {
                let coord: CLLocationCoordinate2D? = (stop.latitude != nil && stop.longitude != nil)
                    ? CLLocationCoordinate2D(latitude: stop.latitude!, longitude: stop.longitude!)
                    : nil
                entries.append(.init(index: entries.count, name: stop.name, isLegBoundary: false, coordinate: coord))
            }
            if let alight = leg.alightStopName, entries.last?.name != alight {
                let coord: CLLocationCoordinate2D? = (leg.alightLatitude != nil && leg.alightLongitude != nil)
                    ? CLLocationCoordinate2D(latitude: leg.alightLatitude!, longitude: leg.alightLongitude!)
                    : nil
                entries.append(.init(index: entries.count, name: alight, isLegBoundary: true, coordinate: coord))
            }
        }

        guard !entries.isEmpty else { isLoading = false; return }

        var geocoded = [Int: MKMapItem]()

        // First pass: use API coordinates directly — no geocoding needed
        for entry in entries {
            if let coord = entry.coordinate {
                let placemark = MKPlacemark(coordinate: coord)
                let item = MKMapItem(placemark: placemark)
                item.name = entry.name
                geocoded[entry.index] = item
            }
        }

        // Second pass: geocode only stops that had no API coordinate
        let needsGeocoding = entries.filter { geocoded[$0.index] == nil }
        if !needsGeocoding.isEmpty {
            await withTaskGroup(of: (Int, MKMapItem?).self) { group in
                for entry in needsGeocoding {
                    let idx = entry.index
                    let q = qualifiedName(entry.name)
                    group.addTask { [weak self] in
                        guard let self else { return (idx, nil) }
                        return (idx, try? await self.findStop(q))
                    }
                }
                for await (idx, item) in group {
                    if let item { geocoded[idx] = item }
                }
            }
        }

        let orderedItems = entries.compactMap { geocoded[$0.index] }
        stopItems = orderedItems
        originItem = orderedItems.first
        destinationItem = orderedItems.last

        // Orange markers only at leg boundaries (not at within-leg intermediates)
        if entries.count > 2 {
            transferItems = entries
                .dropFirst()
                .dropLast()
                .filter { $0.isLegBoundary }
                .compactMap { geocoded[$0.index] }
        }

        // Route: connect all stops in order (API coords make this accurate)
        let coords = orderedItems.map { $0.placemark.coordinate }
        if coords.count >= 2 {
            transitPolylines = [MKPolyline(coordinates: coords, count: coords.count)]
        }

        isLoading = false
    }

    // Prepend "Mannheim " unless the stop already starts with a known RNV city
    nonisolated private func qualifiedName(_ name: String) -> String {
        let knownCities = [
            "Mannheim", "Heidelberg", "Ludwigshafen", "Weinheim",
            "Schwetzingen", "Viernheim", "Lampertheim", "Speyer",
            "Leimen", "Sandhausen", "Walldorf", "Wiesloch",
            "Hockenheim", "Schriesheim", "Heddesheim", "Eppelheim"
        ]
        if knownCities.contains(where: { name.hasPrefix($0) }) {
            return name
        }
        return "Mannheim \(name)"
    }

    nonisolated private func findStop(_ query: String) async throws -> MKMapItem {
        // Try transit POI first so pins land on actual stops
        let transitReq = MKLocalSearch.Request()
        transitReq.naturalLanguageQuery = query
        transitReq.region = Self.rnvRegion
        transitReq.resultTypes = .pointOfInterest
        transitReq.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
        if let resp = try? await MKLocalSearch(request: transitReq).start(),
           let item = resp.mapItems.first {
            return item
        }
        // Fallback to general search
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.region = Self.rnvRegion
        let resp = try await MKLocalSearch(request: req).start()
        guard let item = resp.mapItems.first else {
            throw NSError(domain: "TransitMap", code: 0)
        }
        return item
    }
}

// MARK: - Map View

struct TransitMapViewRepresentable: View {
    let origin: MKMapItem?
    let destination: MKMapItem?
    let route: MKRoute?
    var stopItems: [MKMapItem] = []
    var transferItems: [MKMapItem] = []
    var transitPolylines: [MKPolyline] = []
    var bottomInset: CGFloat = 220
    var realisticElevation: Bool = false
    var mapScope: Namespace.ID? = nil

    private let routeColor = Color(red: 0.25, green: 0.55, blue: 1.0)

    /// Stops that are neither origin nor destination — shown as small inline dots
    private var intermediateStopItems: [MKMapItem] {
        guard stopItems.count > 2 else { return [] }
        return Array(stopItems.dropFirst().dropLast())
    }

    var body: some View {
        mapContent
            .mapStyle(
                realisticElevation
                    ? .standard(elevation: .realistic, pointsOfInterest: .including([.publicTransport]))
                    : .standard(pointsOfInterest: .including([.publicTransport]))
            )
            .safeAreaPadding(.bottom, bottomInset)
    }

    @ViewBuilder
    private var mapContent: some View {
        if let scope = mapScope {
            Map(scope: scope) { mapAnnotations }
                .mapScope(scope)
        } else {
            Map { mapAnnotations }
        }
    }

    @MapContentBuilder
    private var mapAnnotations: some MapContent {
        if let o = origin {
            Annotation(o.name ?? "", coordinate: o.placemark.coordinate, anchor: .bottom) {
                pinView(systemImage: "tram.fill", color: .green, size: 32)
            }
        }
        if let d = destination {
            Annotation(d.name ?? "", coordinate: d.placemark.coordinate, anchor: .bottom) {
                pinView(systemImage: "flag.checkered", color: routeColor, size: 32)
            }
        }
        // Transfer points (leg boundaries between vehicles)
        ForEach(transferItems, id: \.self) { item in
            Annotation(item.name ?? "", coordinate: item.placemark.coordinate, anchor: .bottom) {
                pinView(systemImage: "arrow.triangle.swap", color: .orange, size: 26, iconSize: 11)
            }
        }
        // Small dots for intermediate stops within each leg
        ForEach(intermediateStopItems, id: \.self) { item in
            Annotation("", coordinate: item.placemark.coordinate, anchor: .center) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(routeColor, lineWidth: 2))
            }
        }
        if !mergedCoordinates.isEmpty {
            MapPolyline(coordinates: mergedCoordinates)
                .stroke(routeColor.opacity(0.9), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
        } else if let r = route {
            MapPolyline(r)
                .stroke(routeColor.opacity(0.9), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
        } else if stopItems.count >= 2 {
            MapPolyline(coordinates: stopItems.map { $0.placemark.coordinate })
                .stroke(routeColor.opacity(0.9), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
        }
        UserAnnotation()
    }

    private var mergedCoordinates: [CLLocationCoordinate2D] {
        transitPolylines.flatMap { polyline -> [CLLocationCoordinate2D] in
            var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
            polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
            return coords
        }
    }

    @ViewBuilder
    private func pinView(systemImage: String, color: Color, size: CGFloat, iconSize: CGFloat = 14) -> some View {
        ZStack {
            Circle().fill(color).frame(width: size, height: size)
            Image(systemName: systemImage)
                .foregroundStyle(.white)
                .font(.system(size: iconSize))
        }
    }
}

// MARK: - Full Map Sheet

struct FullMapView: View {
    @ObservedObject var mapVM: TransitMapViewModel
    let legs: [TripLeg]
    @Environment(\.dismiss) private var dismiss

    @Namespace private var mapScope
    @State private var panelHeight: CGFloat = 160

    var body: some View {
        ZStack(alignment: .bottom) {
            TransitMapViewRepresentable(
                origin: mapVM.originItem,
                destination: mapVM.destinationItem,
                route: mapVM.route,
                stopItems: mapVM.stopItems,
                transferItems: mapVM.transferItems,
                transitPolylines: mapVM.transitPolylines,
                bottomInset: 160,
                realisticElevation: true,
                mapScope: mapScope
            )
            .ignoresSafeArea()

            // Map controls – follow the panel
            VStack(spacing: 10) {
                MapUserLocationButton(scope: mapScope)
                MapCompass(scope: mapScope)
                    .mapControlVisibility(.visible)
            }
            .buttonBorderShape(.circle)
            .padding(.trailing, 10)
            .padding(.bottom, panelHeight + 16)
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Scale – bottom left above panel
            MapScaleView(scope: mapScope)
                .mapControlVisibility(.visible)
                .padding(.leading, 16)
                .padding(.bottom, panelHeight + 16)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.28))
                            .font(.system(size: 30))
                    }
                    .padding(.top, 54)
                    .padding(.trailing, 16)
                }
                Spacer()
            }

            RouteStopsPanel(legs: legs, panelHeight: $panelHeight)
        }
        .mapScope(mapScope)
        .ignoresSafeArea()
    }
}

// MARK: - Route Stops Panel

private struct RouteStopEntry {
    enum Kind { case origin, transfer, intermediate, destination }
    let name: String
    let time: String?
    let kind: Kind
}

private enum PanelPosition { case peek, collapsed, expanded }

struct RouteStopsPanel: View {
    let legs: [TripLeg]
    @Binding var panelHeight: CGFloat

    @State private var position: PanelPosition = .collapsed
    @State private var dragOffset: CGFloat = 0
    private let formatter = DateFormattingHelper.shared

    private let peekHeight: CGFloat      = 28
    private let collapsedHeight: CGFloat = 160
    private let expandedHeight: CGFloat  = 400

    private var baseOffset: CGFloat {
        switch position {
        case .peek:      return expandedHeight - peekHeight
        case .collapsed: return expandedHeight - collapsedHeight
        case .expanded:  return 0
        }
    }

    private var currentOffset: CGFloat {
        max(0, min(expandedHeight - peekHeight, baseOffset + dragOffset))
    }

    private var allStops: [RouteStopEntry] { buildStops() }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            switch position {
            case .peek:
                Color.clear.frame(height: 0)
            case .collapsed:
                collapsedContent.transition(.opacity)
            case .expanded:
                expandedContent.transition(.opacity)
            }
        }
        .frame(height: expandedHeight, alignment: .top)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 20, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 20
            )
            .fill(.regularMaterial)
            .shadow(color: .black.opacity(0.18), radius: 14, y: -4)
        )
        .offset(y: currentOffset)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { v in
                    dragOffset = v.translation.height
                    let off = max(0, min(expandedHeight - peekHeight, baseOffset + v.translation.height))
                    panelHeight = expandedHeight - off
                }
                .onEnded { v in
                    let t = v.translation.height
                    let p = v.predictedEndTranslation.height
                    var next = position
                    switch position {
                    case .peek:
                        if t < -20 || p < -60 { next = .collapsed }
                    case .collapsed:
                        if t < -50 || p < -120 { next = .expanded }
                        else if t > 40 || p > 100 { next = .peek }
                    case .expanded:
                        if t > 60 || p > 150 { next = .collapsed }
                    }
                    let targetHeight: CGFloat
                    switch next {
                    case .peek:      targetHeight = peekHeight
                    case .collapsed: targetHeight = collapsedHeight
                    case .expanded:  targetHeight = expandedHeight
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                        position = next
                        dragOffset = 0
                        panelHeight = targetHeight
                    }
                }
        )
    }

    // MARK: Drag Handle

    private var dragHandle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                    switch position {
                    case .peek:
                        position = .collapsed
                        panelHeight = collapsedHeight
                    case .collapsed:
                        position = .expanded
                        panelHeight = expandedHeight
                    case .expanded:
                        position = .collapsed
                        panelHeight = collapsedHeight
                    }
                }
            }
    }

    // MARK: Collapsed

    private var collapsedContent: some View {
        let stops = allStops
        let origin = stops.first
        let dest = stops.count > 1 ? stops.last : nil
        let midCount = max(0, stops.count - 2)

        return VStack(spacing: 0) {
            if let origin { stopRow(origin, isFirst: true) }

            HStack(alignment: .center, spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 2)
                    VStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 3, height: 3)
                        }
                    }
                }
                .frame(width: 20)
                .padding(.leading, 12)

                Text(midCount > 0 ? "\(midCount) Stationen" : "Direktfahrt")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.trailing, 12)
            .fixedSize(horizontal: false, vertical: true)

            if let dest, dest.name != origin?.name { stopRow(dest, isLast: true) }
        }
        .padding(.bottom, 16)
    }

    // MARK: Expanded

    private var expandedContent: some View {
        let stops = allStops
        guard stops.count >= 2 else { return AnyView(EmptyView()) }

        return AnyView(
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                        stopRow(stop, isFirst: i == 0, isLast: i == stops.count - 1)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.bottom, 16)
            }
        )
    }

    // MARK: Stop Row

    @ViewBuilder
    private func stopRow(_ stop: RouteStopEntry, isFirst: Bool = false, isLast: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 0) {
            ZStack {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.secondary.opacity(isFirst ? 0 : 0.22))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                    Rectangle()
                        .fill(Color.secondary.opacity(isLast ? 0 : 0.22))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
                dotView(for: stop)
            }
            .frame(width: 20)
            .padding(.leading, 12)

            HStack {
                Text(stop.name)
                    .font(stop.kind == .intermediate ? .caption : .subheadline)
                    .fontWeight(stop.kind == .intermediate ? .regular : .medium)
                    .foregroundColor(stop.kind == .intermediate ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                if let time = stop.time {
                    Text(formatter.formatTime(time))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func dotView(for stop: RouteStopEntry) -> some View {
        switch stop.kind {
        case .origin:
            Circle().fill(Color.green).frame(width: 12, height: 12)
        case .destination:
            Circle().fill(Color(red: 0.25, green: 0.55, blue: 1.0)).frame(width: 12, height: 12)
        case .transfer:
            Circle().fill(Color.orange).frame(width: 10, height: 10)
        case .intermediate:
            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
        }
    }

    // MARK: Build Stop List

    private func buildStops() -> [RouteStopEntry] {
        var result: [RouteStopEntry] = []
        let timedLegs = legs.filter { $0.isTimedLeg }

        for (index, leg) in timedLegs.enumerated() {
            let isFirstLeg = index == 0
            let isLastLeg = index == timedLegs.count - 1

            if let name = leg.boardStopName {
                let kind: RouteStopEntry.Kind = isFirstLeg ? .origin : .transfer
                let time = leg.estimatedDepartureTime ?? leg.departureTime
                if result.last?.name != name {
                    result.append(RouteStopEntry(name: name, time: time, kind: kind))
                }
            }

            for stop in leg.intermediateStops {
                let time = stop.estimatedTime ?? stop.scheduledTime
                result.append(RouteStopEntry(name: stop.name, time: time, kind: .intermediate))
            }

            if isLastLeg, let name = leg.alightStopName {
                let time = leg.estimatedArrivalTime ?? leg.arrivalTime
                if result.last?.name != name {
                    result.append(RouteStopEntry(name: name, time: time, kind: .destination))
                }
            }
        }

        return result
    }
}
