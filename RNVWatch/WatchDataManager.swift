// Lädt Fahrten aus dem gemeinsamen App-Group-UserDefaults.

import Foundation
import Combine

@MainActor
class WatchDataManager: ObservableObject {
    @Published var activeTrip: WidgetTripData? = nil
    @Published var savedTrips: [TripData] = []
    @Published var lastRefresh: Date? = nil

    private let appGroupID = "group.com.stefanfriedrich.rnvapp"
    private var refreshTimer: Timer? = nil

    init() {
        startAutoRefresh()
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Laden

    func refresh() {
        let defaults = UserDefaults(suiteName: appGroupID)
        activeTrip = loadActiveTrip(from: defaults)
        savedTrips = loadSavedTrips(from: defaults)
        lastRefresh = Date()
    }

    // MARK: - Aktive Fahrt

    private func loadActiveTrip(from defaults: UserDefaults?) -> WidgetTripData? {
        guard let defaults,
              let data = defaults.data(forKey: "savedTripData") else { return nil }

        let activeIDs = Set(defaults.stringArray(forKey: "activeTrips") ?? [])
        guard !activeIDs.isEmpty else { return nil }

        let now = Date()
        let allTrips = (try? JSONDecoder().decode([WidgetTripData].self, from: data)) ?? []

        return allTrips
            .filter { activeIDs.contains($0.id) }
            .filter { trip in
                guard let end = WatchDateHelper.parse(trip.endTime) else { return false }
                return end > now
            }
            .sorted {
                let a = WatchDateHelper.parse($0.startTime) ?? .distantFuture
                let b = WatchDateHelper.parse($1.startTime) ?? .distantFuture
                return a < b
            }
            .first
    }

    // MARK: - Geplante Fahrten

    private func loadSavedTrips(from defaults: UserDefaults?) -> [TripData] {
        guard let defaults,
              let data = defaults.data(forKey: "plannedTripData") else { return [] }

        let trips = (try? JSONDecoder().decode([TripData].self, from: data)) ?? []
        let now = Date()

        return trips
            .filter { trip in
                guard let end = WatchDateHelper.parse(trip.endTime) else { return false }
                return end > now
            }
            .sorted {
                let a = WatchDateHelper.parse($0.startTime) ?? .distantFuture
                let b = WatchDateHelper.parse($1.startTime) ?? .distantFuture
                return a < b
            }
    }
}
