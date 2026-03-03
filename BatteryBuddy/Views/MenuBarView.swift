import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @ObservedObject var batteryMonitor: BatteryMonitor
    @ObservedObject var processMonitor: ProcessMonitor
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summarySection
            Divider().padding(.vertical, 8)
            processSection
            Divider().padding(.vertical, 8)
            insightsSection
            Divider().padding(.vertical, 8)
            footerSection
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: batteryMonitor.batteryInfo.menuBarIcon)
                    .font(.system(size: 28))
                    .foregroundStyle(batteryColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(batteryMonitor.batteryInfo.percentage)%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("Health: \(batteryMonitor.batteryInfo.healthPercentage)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(timeRemainingText)
                        .font(.system(.title3, weight: .semibold))
                }

                Spacer()
            }

            if batteryMonitor.batteryInfo.powerDrawWatts > 0 {
                Text(batteryMonitor.batteryInfo.formattedPowerDraw)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(summaryText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .italic()
        }
    }

    private var timeRemainingText: String {
        let info = batteryMonitor.batteryInfo
        if info.isFullyCharged {
            return "Fully charged"
        }
        if info.isCharging {
            return "\(info.formattedTimeRemaining) to full"
        }
        return "\(info.formattedTimeRemaining) remaining"
    }

    private var summaryText: String {
        let info = batteryMonitor.batteryInfo
        if info.isFullyCharged && info.isPluggedIn {
            return info.summary
        }

        let heavyDrainers = processMonitor.topProcesses
            .filter { $0.isHeavy }
            .prefix(2)
            .map(\.displayName)

        if !heavyDrainers.isEmpty {
            return "Heavy usage — \(heavyDrainers.joined(separator: " and ")) \(heavyDrainers.count == 1 ? "is" : "are") eating your battery"
        }

        // Show top app even when not "heavy"
        if let top = processMonitor.topProcesses.first, top.cpuUsage > 3.0 {
            return "\(top.displayName) is the most active app right now"
        }

        return info.summary
    }

    private var batteryColor: Color {
        let pct = batteryMonitor.batteryInfo.percentage
        if batteryMonitor.batteryInfo.isCharging { return .green }
        if pct <= 10 { return .red }
        if pct <= 20 { return .orange }
        return .primary
    }

    // MARK: - Process List

    private var processSection: some View {
        ProcessListView(processes: processMonitor.topProcesses)
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Insights")
                .font(.headline)

            let insights = processMonitor.generateInsights(battery: batteryMonitor.batteryInfo)
            ForEach(insights, id: \.self) { insight in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(.top, 2)

                    Text(insight)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: launchAtLogin) { _, newValue in
                    toggleLoginItem(enabled: newValue)
                }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func toggleLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enabled
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}
