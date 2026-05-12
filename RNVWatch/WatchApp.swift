// RNVWatch – Apple Watch App für Mannheim ÖPNV

import SwiftUI

@main
struct RNVWatchApp: App {
    @StateObject private var dataManager = WatchDataManager()
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
                .environmentObject(connectivity)
                .onAppear {
                    dataManager.refresh()
                    connectivity.onContextUpdated = { [weak dataManager] in
                        dataManager?.refresh()
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                dataManager.refresh()
                dataManager.startAutoRefresh()
            } else if phase == .background || phase == .inactive {
                dataManager.stopAutoRefresh()
            }
        }
    }
}
