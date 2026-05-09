#if DEBUG
import Foundation

enum WatchDemoData {

    // MARK: - Zeithelfer

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func isoString(from date: Date) -> String {
        iso.string(from: date)
    }

    private static func future(_ minutes: Double) -> String {
        isoString(from: Date().addingTimeInterval(minutes * 60))
    }

    // MARK: - Aktive Fahrt

    static let activeTrip = WidgetTripData(
        id: "demo-active-1",
        startTime: future(6),
        endTime: future(28),
        interchanges: 1,
        startStation: "MA Hauptbahnhof",
        endStation: "MA Paradeplatz",
        legs: [
            WidgetTripLegData(
                legType: "timedLeg",
                boardStopName: "MA Hauptbahnhof",
                alightStopName: "MA Tattersall",
                departureTime: future(6),
                arrivalTime: future(14),
                serviceName: "4",
                serviceType: "STRASSENBAHN",
                destinationLabel: "Kirchheim"
            ),
            WidgetTripLegData(
                legType: "interchange",
                boardStopName: nil,
                alightStopName: nil,
                departureTime: nil,
                arrivalTime: nil,
                serviceName: nil,
                serviceType: nil,
                destinationLabel: nil
            ),
            WidgetTripLegData(
                legType: "timedLeg",
                boardStopName: "MA Tattersall",
                alightStopName: "MA Paradeplatz",
                departureTime: future(17),
                arrivalTime: future(28),
                serviceName: "6",
                serviceType: "STRASSENBAHN",
                destinationLabel: "MA Neuostheim"
            )
        ]
    )

    // MARK: - Geplante Fahrten

    static let savedTrips: [TripData] = [
        TripData(
            id: "demo-saved-1",
            startTime: future(14),
            endTime: future(47),
            interchanges: 0,
            startStation: "MA Wasserturm",
            endStation: "HD Hauptbahnhof",
            legs: [
                TripLegData(
                    legType: "timedLeg",
                    boardStopName: "MA Wasserturm",
                    alightStopName: "HD Hauptbahnhof",
                    departureTime: future(14),
                    arrivalTime: future(47),
                    serviceName: "S3",
                    serviceType: "S_BAHN",
                    destinationLabel: "Karlsruhe Hbf",
                    intermediateStopNames: ["MA Friedrichspark", "MA Seckenheim", "Heidelberg-Wieblingen"]
                )
            ]
        ),
        TripData(
            id: "demo-saved-2",
            startTime: future(42),
            endTime: future(79),
            interchanges: 1,
            startStation: "MA Paradeplatz",
            endStation: "LU Hauptbahnhof",
            legs: [
                TripLegData(
                    legType: "timedLeg",
                    boardStopName: "MA Paradeplatz",
                    alightStopName: "MA Hbf Kurpfalzbrücke",
                    departureTime: future(42),
                    arrivalTime: future(55),
                    serviceName: "10",
                    serviceType: "STRASSENBAHN",
                    destinationLabel: "LU Oggersheim",
                    intermediateStopNames: nil
                ),
                TripLegData(
                    legType: "timedLeg",
                    boardStopName: "MA Hbf Kurpfalzbrücke",
                    alightStopName: "LU Hauptbahnhof",
                    departureTime: future(60),
                    arrivalTime: future(79),
                    serviceName: "70",
                    serviceType: "BUS",
                    destinationLabel: "LU Oppau",
                    intermediateStopNames: nil
                )
            ]
        ),
        TripData(
            id: "demo-saved-3",
            startTime: future(90),
            endTime: future(118),
            interchanges: 0,
            startStation: "HD Bismarckplatz",
            endStation: "MA Paradeplatz",
            legs: [
                TripLegData(
                    legType: "timedLeg",
                    boardStopName: "HD Bismarckplatz",
                    alightStopName: "MA Paradeplatz",
                    departureTime: future(90),
                    arrivalTime: future(118),
                    serviceName: "RNV 5",
                    serviceType: "STRASSENBAHN",
                    destinationLabel: "MA Schönau",
                    intermediateStopNames: ["HD Rohrbacher Str.", "MA Neuostheim", "MA Oststadt"]
                )
            ]
        )
    ]

    // MARK: - Abfahrten

    static let departures: [WatchDeparture] = [
        WatchDeparture(
            id: "demo-dep-1",
            lineName: "4",
            direction: "Kirchheim",
            scheduledTime: future(3),
            estimatedTime: future(5),
            serviceType: "STRASSENBAHN",
            delayMinutes: 2
        ),
        WatchDeparture(
            id: "demo-dep-2",
            lineName: "6",
            direction: "MA Neuostheim",
            scheduledTime: future(7),
            estimatedTime: future(7),
            serviceType: "STRASSENBAHN",
            delayMinutes: 0
        ),
        WatchDeparture(
            id: "demo-dep-3",
            lineName: "S3",
            direction: "Karlsruhe Hbf",
            scheduledTime: future(12),
            estimatedTime: nil,
            serviceType: "S_BAHN",
            delayMinutes: nil
        ),
        WatchDeparture(
            id: "demo-dep-4",
            lineName: "63",
            direction: "BASF Tor 1",
            scheduledTime: future(18),
            estimatedTime: future(18),
            serviceType: "BUS",
            delayMinutes: 0
        ),
        WatchDeparture(
            id: "demo-dep-5",
            lineName: "RB 38",
            direction: "Heidelberg Hbf",
            scheduledTime: future(24),
            estimatedTime: future(27),
            serviceType: "REGIONAL",
            delayMinutes: 3
        )
    ]
}
#endif
