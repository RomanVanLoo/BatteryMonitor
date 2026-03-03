import SwiftUI

struct StatusItemView: View {
    let batteryInfo: BatteryInfo

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryInfo.menuBarIcon)
            Text(batteryInfo.menuBarText)
                .monospacedDigit()
        }
    }
}
