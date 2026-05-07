// RNVWatch – Apple Watch App für Mannheim ÖPNV

import SwiftUI

@main
struct RNVWatchApp: App {
    @StateObject private var dataManager = WatchDataManager()
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
                .environmentObject(connectivity)
                .onAppear { dataManager.refresh() }
        }
    }
}
