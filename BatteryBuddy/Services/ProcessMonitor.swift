import Foundation
import AppKit
import Combine

final class ProcessMonitor: ObservableObject {
    @Published private(set) var topProcesses: [EnergyProcess] = []

    private var timer: Timer?
    private weak var batteryMonitor: BatteryMonitor?

    init(batteryMonitor: BatteryMonitor) {
        self.batteryMonitor = batteryMonitor
        DispatchQueue.main.async { [weak self] in
            self?.update()
            self?.timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.update()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func update() {
        // Capture battery info on main thread to avoid racing with BatteryMonitor writes.
        let powerDraw = batteryMonitor?.batteryInfo.powerDrawWatts ?? 0
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let raw = self.fetchProcesses()
            let grouped = self.groupByApp(raw, totalPower: powerDraw)
            let top = Array(grouped.prefix(10))

            DispatchQueue.main.async {
                self.topProcesses = top
            }
        }
    }

    func generateInsights(battery: BatteryInfo) -> [String] {
        if battery.isFullyCharged {
            return topProcesses.isEmpty
                ? ["Fully charged — no battery concerns"]
                : ["Fully charged — \(topProcesses.first?.displayName ?? "nothing") is the most active app"]
        }

        if battery.isCharging {
            if let top = topProcesses.first, top.cpuUsage > 3.0 {
                return ["\(top.displayName) is the most active app — may slow charging"]
            }
            return ["Charging — no significant drainers"]
        }

        var insights: [String] = []
        let totalCPU = topProcesses.reduce(0.0) { $0 + $1.cpuUsage }

        // Show "close X to gain Y" for the top drainers, even moderate ones
        for process in topProcesses.prefix(2) where process.cpuUsage > 1.0 {
            guard totalCPU > 0, let timeRemaining = battery.timeRemainingMinutes, timeRemaining > 0 else { continue }
            let fraction = process.cpuUsage / totalCPU
            let additionalMinutes = Int(Double(timeRemaining) * fraction / max(1.0 - fraction, 0.01))
            if additionalMinutes > 2 {
                insights.append("If you closed \(process.displayName), you'd gain ~\(additionalMinutes.formattedDuration)")
            }
        }

        let notableDrainers = topProcesses.filter { $0.cpuUsage > 2.0 }
        if notableDrainers.count > 2 {
            insights.append("\(notableDrainers.count) apps running with notable energy use")
        }

        if let timeRemaining = battery.timeRemainingMinutes {
            if timeRemaining < 60 {
                insights.append("Under an hour left — consider closing unused apps")
            } else if timeRemaining < 120 {
                insights.append("About \(timeRemaining.formattedDuration) left — keep an eye on heavy apps")
            }
        }

        if insights.isEmpty {
            if let top = topProcesses.first, top.cpuUsage > 0.5 {
                insights.append("\(top.displayName) is your top energy user right now")
            } else {
                insights.append("Very light usage — battery is draining slowly")
            }
        }

        return insights
    }

    // MARK: - Private

    private struct RawProcess {
        let pid: pid_t
        let ppid: pid_t
        let cpu: Double
        let command: String
    }

    private func fetchProcesses() -> [RawProcess] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-A", "-o", "pid=,ppid=,%cpu=,comm="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return []
        }

        // Read ALL data before waitUntilExit — otherwise the pipe buffer fills
        // (ps -A outputs hundreds of lines) and both processes deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [RawProcess] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = pid_t(parts[0]),
                  let ppid = pid_t(parts[1]),
                  let cpu = Double(parts[2]) else { continue }

            let command = String(parts[3])
            results.append(RawProcess(pid: pid, ppid: ppid, cpu: cpu, command: command))
        }

        return results
    }

    // Base system overhead that isn't attributable to any process:
    // display (~4-8W depending on brightness), SSD, RAM, Wi-Fi, Thunderbolt, etc.
    // Conservative estimate — real value varies with brightness and peripherals.
    private static let baseSystemWatts: Double = 6.0

    private func groupByApp(_ processes: [RawProcess], totalPower: Double) -> [EnergyProcess] {
        var totalCPU = 0.0
        for proc in processes {
            totalCPU += proc.cpu
        }

        var groups: [String: (displayName: String, cpu: Double, icon: NSImage, pids: [pid_t])] = [:]
        let genericIcon = NSWorkspace.shared.icon(for: .applicationBundle)

        for proc in processes where proc.cpu > 0.1 {
            let resolved = resolveApp(pid: proc.pid, ppid: proc.ppid, command: proc.command)
            let key = resolved.key
            let displayName = resolved.displayName
            let icon = resolved.icon ?? genericIcon

            if var existing = groups[key] {
                existing.cpu += proc.cpu
                existing.pids.append(proc.pid)
                groups[key] = existing
            } else {
                groups[key] = (displayName: displayName, cpu: proc.cpu, icon: icon, pids: [proc.pid])
            }
        }

        // Only attribute CPU-driven power to processes, not display/hardware overhead.
        let cpuAttributablePower = max(0, totalPower - Self.baseSystemWatts)

        return groups.map { key, value in
            let estimatedWatts = totalCPU > 0 ? (value.cpu / totalCPU) * cpuAttributablePower : 0
            return EnergyProcess(
                id: key,
                displayName: value.displayName,
                cpuUsage: value.cpu,
                estimatedWatts: estimatedWatts,
                icon: value.icon,
                isHeavy: value.cpu > 10.0,
                processCount: value.pids.count
            )
        }
        .sorted { $0.cpuUsage > $1.cpuUsage }
    }

    private struct ResolvedApp {
        let key: String
        let displayName: String
        let icon: NSImage?
    }

    private func resolveApp(pid: pid_t, ppid: pid_t, command: String) -> ResolvedApp {
        if let app = NSRunningApplication(processIdentifier: pid),
           let bundleId = app.bundleIdentifier {
            return ResolvedApp(
                key: bundleId,
                displayName: app.localizedName ?? command.components(separatedBy: "/").last ?? command,
                icon: app.icon
            )
        }

        if let path = pathForPID(pid),
           let bundlePath = appBundlePath(from: path) {
            let bundle = Bundle(path: bundlePath)
            let name = bundle?.infoDictionary?["CFBundleName"] as? String
                ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
                ?? URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: bundlePath)
            let key = bundle?.bundleIdentifier ?? bundlePath
            return ResolvedApp(key: key, displayName: name, icon: icon)
        }

        if let parentApp = NSRunningApplication(processIdentifier: ppid),
           let bundleId = parentApp.bundleIdentifier {
            return ResolvedApp(
                key: bundleId,
                displayName: parentApp.localizedName ?? command.components(separatedBy: "/").last ?? command,
                icon: parentApp.icon
            )
        }

        let processName = command.components(separatedBy: "/").last ?? command
        let humanName = Self.knownProcessNames[processName] ?? processName
        return ResolvedApp(key: processName, displayName: humanName, icon: nil)
    }

    private static let knownProcessNames: [String: String] = [
        "kernel_task": "macOS System",
        "WindowServer": "Window Server",
        "mds_stores": "Spotlight",
        "mds": "Spotlight",
        "mdworker": "Spotlight",
        "mdworker_shared": "Spotlight",
        "com.docker.hyperkit": "Docker",
        "com.docker.vmnetd": "Docker",
        "containerd": "Docker",
        "coreaudiod": "Core Audio",
        "bluetoothd": "Bluetooth",
        "sharingd": "AirDrop/Sharing",
        "cloudd": "iCloud Sync",
        "nsurlsessiond": "Network Downloads",
        "trustd": "Security",
        "distnoted": "Notification Center",
        "syslogd": "System Log",
    ]
}
