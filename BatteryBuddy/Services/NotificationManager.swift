import Foundation
import UserNotifications

final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private var lastLowBatteryNotification: Date?
    private var lastHighDrainNotification: Date?
    private var appSpikeCooldowns: [String: Date] = [:]
    private var previousTimeRemaining: Int?
    private var previousTopProcess: (name: String, cpu: Double)?

    private let cooldownInterval: TimeInterval = 1800 // 30 minutes

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        requestPermission()
    }

    func checkAndNotify(battery: BatteryInfo, processes: [EnergyProcess]) {
        guard !battery.isPluggedIn else {
            previousTimeRemaining = nil
            previousTopProcess = nil
            return
        }

        checkLowBattery(battery: battery, processes: processes)
        checkAppSpike(battery: battery, processes: processes)
        checkHighDrainRate(battery: battery)

        previousTimeRemaining = battery.timeRemainingMinutes
        if let top = processes.first {
            previousTopProcess = (name: top.displayName, cpu: top.cpuUsage)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // MARK: - Private

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkLowBattery(battery: BatteryInfo, processes: [EnergyProcess]) {
        guard battery.percentage <= 20,
              !isOnCooldown(lastLowBatteryNotification) else { return }

        let topDrainer = processes.first?.displayName ?? "Unknown"
        let timeStr: String
        if let minutes = battery.timeRemainingMinutes {
            timeStr = "about \(minutes.formattedDuration)"
        } else {
            timeStr = "limited time"
        }

        send(
            id: "low-battery",
            title: "Battery Low — \(battery.percentage)%",
            body: "You have \(timeStr) left. \(topDrainer) is using the most power."
        )
        lastLowBatteryNotification = Date()
    }

    private func checkAppSpike(battery: BatteryInfo, processes: [EnergyProcess]) {
        guard let top = processes.first,
              let prev = previousTopProcess,
              let currentTime = battery.timeRemainingMinutes,
              let prevTime = previousTimeRemaining else { return }

        // Detect if an app's CPU usage roughly doubled and time dropped significantly
        let timeDropped = prevTime - currentTime
        let timeDrop = Double(timeDropped) / Double(max(prevTime, 1))

        let isNewSpike = top.displayName != prev.name && top.cpuUsage > 20.0
        let isSameAppSpike = top.displayName == prev.name && top.cpuUsage > prev.cpu * 2.0

        guard (isNewSpike || isSameAppSpike) && timeDrop > 0.2,
              !isOnCooldown(appSpikeCooldowns[top.id]) else { return }

        send(
            id: "app-spike-\(top.id)",
            title: "\(top.displayName) Energy Spike",
            body: "\(top.displayName) just started using significantly more power. Estimated time dropped from \(prevTime.formattedDuration) to \(currentTime.formattedDuration)."
        )
        appSpikeCooldowns[top.id] = Date()
    }

    private func checkHighDrainRate(battery: BatteryInfo) {
        guard let minutes = battery.timeRemainingMinutes,
              battery.percentage > 20,
              battery.powerDrawWatts > 20,
              !isOnCooldown(lastHighDrainNotification) else { return }

        let depletionTime = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let timeStr = depletionTime.map { formatter.string(from: $0) } ?? "soon"

        send(
            id: "high-drain",
            title: "Unusually High Drain",
            body: "You're draining faster than usual. At this rate you'll hit 0% by \(timeStr)."
        )
        lastHighDrainNotification = Date()
    }

    private func isOnCooldown(_ lastNotification: Date?) -> Bool {
        guard let last = lastNotification else { return false }
        return Date().timeIntervalSince(last) < cooldownInterval
    }

    private func send(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
