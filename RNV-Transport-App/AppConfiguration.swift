import Foundation

struct AppConfiguration {
    // ✅ ZENTRALE APP GROUP ID
    static let appGroupID = "group.com.stefanfriedrich.rnvapp"
    
    // ⚠️ WICHTIG: Diese Werte MÜSSEN vor dem Build gesetzt werden!
    static let teamID = "YOUR_TEAM_ID" // Ersetze mit deiner Apple Team ID
    
    // MARK: - Feature Flags
    static let enableOfflineMode = false
    static let enableAutoBackup = true
    static let enableDetailedLogging = false
    
    // MARK: - API Configuration
    static let requestTimeout: TimeInterval = 30.0
    static let resourceTimeout: TimeInterval = 60.0
    
    // MARK: - Update Intervals (adaptiv)
    static let updateIntervalBeforeDeparture: TimeInterval = 30 // 30 Sekunden
    static let updateIntervalDuringJourney: TimeInterval = 10   // 10 Sekunden
    static let updateIntervalNearArrival: TimeInterval = 5      // 5 Sekunden
    
    // MARK: - Validation
    static func validateConfiguration() -> [String] {
        var errors: [String] = []
        
        #if DEBUG
        if teamID == "YOUR_TEAM_ID" {
            errors.append("⚠️ teamID nicht konfiguriert - App Group wird nicht funktionieren")
        }
        #endif
        
        return errors
    }
}