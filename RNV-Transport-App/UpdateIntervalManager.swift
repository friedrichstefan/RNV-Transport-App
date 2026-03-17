import Foundation

class UpdateIntervalManager {
    private let formatter = DateFormattingHelper.shared
    
    func getUpdateInterval(
        departureTimeISO: String,
        arrivalTimeISO: String,
        currentTime: Date = Date()
    ) -> TimeInterval {
        guard let departureDate = formatter.parseISO8601(departureTimeISO),
              let arrivalDate = formatter.parseISO8601(arrivalTimeISO) else {
            return 30 // Default
        }
        
        let timeUntilDeparture = departureDate.timeIntervalSince(currentTime)
        let timeUntilArrival = arrivalDate.timeIntervalSince(currentTime)
        
        // ✅ Adaptives Intervall
        if timeUntilDeparture > 0 {
            // Vor Abfahrt: Je näher desto häufiger
            if timeUntilDeparture > 600 {
                return 60 // 1 Minute
            } else if timeUntilDeparture > 300 {
                return 30 // 30 Sekunden
            } else {
                return 10 // 10 Sekunden
            }
        } else if timeUntilArrival > 0 {
            // Während der Fahrt: Je näher desto häufiger
            if timeUntilArrival > 600 {
                return 30 // 30 Sekunden
            } else if timeUntilArrival > 300 {
                return 10 // 10 Sekunden
            } else {
                return 5 // 5 Sekunden
            }
        }
        
        return 60 // Nach Ankunft selten
    }
}