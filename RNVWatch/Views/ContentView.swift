import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataManager: WatchDataManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ActiveTripView()
                .tag(0)
                .tabItem { Label("Fahrt", systemImage: "tram.fill") }

            SavedTripsView()
                .tag(1)
                .tabItem { Label("Geplant", systemImage: "calendar") }

            DeparturesView()
                .tag(2)
                .tabItem { Label("Abfahrten", systemImage: "clock") }
        }
    }
}
