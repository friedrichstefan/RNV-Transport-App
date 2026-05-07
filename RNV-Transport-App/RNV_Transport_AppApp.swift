//
//  RNV_Transport_AppApp.swift
//  RNV-Transport-App
//
//  Created by Friedrich, Stefan on 09.01.26.
//

import SwiftUI
import ActivityKit

// MARK: - App Delegate (für Background Task Registration)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // BGTask MUSS vor dem Ende von didFinishLaunchingWithOptions registriert werden
        if #available(iOS 16.2, *) {
            LiveActivityManager.registerBackgroundTask()
        }

        // Konfiguration in DEBUG prüfen
        #if DEBUG
        let configErrors = AppConfiguration.validateConfiguration()
        for error in configErrors {
            print("⚠️ [CONFIG] \(error)")
        }
        #endif

        return true
    }

    // MARK: - Orientierung auf Portrait beschränken

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .portrait
    }
}

// MARK: - App Entry Point

@main
struct RNV_Transport_AppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var liveActivityManager = LiveActivityManager()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasSeenOnboarding {
                ContentView()
                    .environmentObject(liveActivityManager)
            } else {
                OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
            }
        }
    }
}
