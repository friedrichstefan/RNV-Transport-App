import SwiftUI

struct TransportIconHelper {
    static func getLineColor(for serviceType: String?) -> Color {
        switch serviceType {
        case "STRASSENBAHN": return .red
        case "BUS": return .blue
        case "S_BAHN": return .green
        default: return .gray
        }
    }
    
    static func getTransportIcon(for serviceType: String?) -> String {
        switch serviceType {
        case "STRASSENBAHN": return "tram.fill"
        case "BUS": return "bus.fill"
        case "S_BAHN": return "train.side.front.car"
        default: return "questionmark"
        }
    }
    
    static func getShortLineName(from serviceName: String?) -> String {
        guard let name = serviceName else { return "?" }
        return name.replacingOccurrences(of: "RNV ", with: "")
    }
}