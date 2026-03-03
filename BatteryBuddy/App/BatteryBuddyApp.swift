import SwiftUI
import Combine

@main
struct BatteryBuddyApp: App {
    @StateObject private var batteryMonitor: BatteryMonitor
    @StateObject private var processMonitor: ProcessMonitor
    @StateObject private var notificationManager: NotificationManager

    init() {
        let bm = BatteryMonitor()
        let pm = ProcessMonitor(batteryMonitor: bm)
        _batteryMonitor = StateObject(wrappedValue: bm)
        _processMonitor = StateObject(wrappedValue: pm)
        _notificationManager = StateObject(wrappedValue: NotificationManager())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                batteryMonitor: batteryMonitor,
                processMonitor: processMonitor
            )
        } label: {
            StatusItemView(batteryInfo: batteryMonitor.batteryInfo)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: batteryMonitor.batteryInfo.percentage) { _, _ in
            notificationManager.checkAndNotify(
                battery: batteryMonitor.batteryInfo,
                processes: processMonitor.topProcesses
            )
        }
    }
}
