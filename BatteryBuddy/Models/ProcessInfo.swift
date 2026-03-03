import AppKit

struct EnergyProcess: Identifiable {
    let id: String
    let displayName: String
    let cpuUsage: Double
    let estimatedWatts: Double
    let icon: NSImage
    let isHeavy: Bool
    let processCount: Int

    var formattedPower: String {
        if estimatedWatts >= 1.0 {
            return String(format: "%.1fW", estimatedWatts)
        }
        if estimatedWatts >= 0.01 {
            return String(format: "%.0fmW", estimatedWatts * 1000)
        }
        return "<10mW"
    }

    var impactLabel: String {
        if isHeavy { return "Heavy" }
        if cpuUsage > 3.0 { return "Moderate" }
        return "Low"
    }
}
