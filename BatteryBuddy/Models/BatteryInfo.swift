import Foundation

struct BatteryInfo {
    var percentage: Int = 0
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var currentCapacity: Int = 0
    var maxCapacity: Int = 0
    var designCapacity: Int = 0
    // Actual mAh values (Apple Silicon reports CurrentCapacity/MaxCapacity as percentages)
    var rawCurrentCapacityMah: Int = 0
    var rawMaxCapacityMah: Int = 0
    var cycleCount: Int = 0
    var voltage: Double = 0
    var amperage: Double = 0
    var temperature: Double = 0
    var health: Double = 0
    var powerDrawWatts: Double = 0
    var timeRemainingMinutes: Int?
    var timeToFullMinutes: Int?
    var isFullyCharged: Bool = false

    var healthPercentage: String {
        String(format: "%.0f%%", health)
    }

    var compactTime: String {
        guard let minutes = isCharging ? timeToFullMinutes : timeRemainingMinutes else {
            return "..."
        }
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%d:%02d", h, m)
    }

    var formattedTimeRemaining: String {
        guard let minutes = isCharging ? timeToFullMinutes : timeRemainingMinutes else {
            return "..."
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    var menuBarText: String {
        if isFullyCharged && isPluggedIn {
            return "100% — Charged"
        }
        return "\(percentage)% - \(compactTime)"
    }

    var menuBarIcon: String {
        if isCharging || isPluggedIn {
            return "battery.100.bolt"
        }
        switch percentage {
        case 76...100: return "battery.100"
        case 51...75: return "battery.75"
        case 26...50: return "battery.50"
        case 11...25: return "battery.25"
        default: return "battery.0"
        }
    }

    var formattedPowerDraw: String {
        String(format: "Currently drawing %.1fW", powerDrawWatts)
    }

    var summary: String {
        if isFullyCharged && isPluggedIn {
            return "Fully charged and plugged in"
        }
        if isCharging {
            return "Charging — \(formattedTimeRemaining) to full"
        }
        if powerDrawWatts > 15 {
            return "Heavy usage — draining fast"
        }
        if powerDrawWatts > 8 {
            return "Moderate usage"
        }
        return "Light usage — your battery should last a while"
    }
}
