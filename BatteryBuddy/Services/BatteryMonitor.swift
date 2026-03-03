import Foundation
import AppKit
import IOKit
import IOKit.ps
import Combine

final class BatteryMonitor: ObservableObject {
    @Published private(set) var batteryInfo = BatteryInfo()

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Percentage-history approach: record a timestamp each time the percentage
    // changes. The drain/charge rate is computed from the *full* history since
    // launch (or since the last reset), so it gets more accurate over time.
    private var percentageSamples: [(date: Date, percentage: Int)] = []
    private var lastPercentageChangeDate = Date()
    private var historicalRatePerMinute: Double?

    // Amperage EMA — used as a fallback before enough percentage data exists.
    private var smoothedAmperage: Double = 0
    private let emaAlpha: Double = 0.15

    // Track state changes that invalidate history.
    private var lastChargingState: Bool?

    // IOKit power source change callback — fires instantly on plug/unplug.
    private var powerSourceLoop: CFRunLoopSource?

    init() {
        observeSleepWake()
        observePowerSourceChanges()
        update()
        startTimer()
    }

    deinit {
        timer?.invalidate()
        if let loop = powerSourceLoop {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), loop, .defaultMode)
        }
    }

    func update() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, nil, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return }

        var info = BatteryInfo()

        info.currentCapacity = dict["CurrentCapacity"] as? Int ?? 0
        info.maxCapacity = dict["MaxCapacity"] as? Int ?? 0
        info.designCapacity = dict["DesignCapacity"] as? Int ?? 0
        info.cycleCount = dict["CycleCount"] as? Int ?? 0
        info.voltage = Double(dict["Voltage"] as? Int ?? 0)
        info.amperage = Double(dict["Amperage"] as? Int ?? 0)
        info.temperature = Double(dict["Temperature"] as? Int ?? 0) / 100.0
        info.isCharging = dict["IsCharging"] as? Bool ?? false
        info.isPluggedIn = dict["ExternalConnected"] as? Bool ?? false
        info.isFullyCharged = dict["FullyCharged"] as? Bool ?? false

        // Apple Silicon reports CurrentCapacity/MaxCapacity as percentages (0-100),
        // not mAh. The actual mAh values live under AppleRaw* keys.
        info.rawCurrentCapacityMah = dict["AppleRawCurrentCapacity"] as? Int ?? info.currentCapacity
        info.rawMaxCapacityMah = dict["AppleRawMaxCapacity"] as? Int ?? info.maxCapacity

        if info.maxCapacity > 0 {
            info.percentage = Int((Double(info.currentCapacity) / Double(info.maxCapacity)) * 100.0)
        }

        // Health: compare actual mAh max to design mAh
        if info.designCapacity > 0 && info.rawMaxCapacityMah > 0 {
            info.health = (Double(info.rawMaxCapacityMah) / Double(info.designCapacity)) * 100.0
        }

        if info.voltage > 0 && info.amperage != 0 {
            info.powerDrawWatts = abs(info.voltage * info.amperage) / 1_000_000.0
        }

        // Reset history when charge state flips (plug in / unplug),
        // but not on the very first read (lastChargingState is nil).
        if let previous = lastChargingState, info.isCharging != previous {
            resetHistory()
        }
        lastChargingState = info.isCharging

        recordPercentage(info.percentage)
        updateSmoothedAmperage(abs(info.amperage))

        if info.isFullyCharged {
            info.timeRemainingMinutes = nil
            info.timeToFullMinutes = nil
        } else if info.isCharging {
            info.timeToFullMinutes = estimateTimeToFull(
                currentPercentage: info.percentage,
                rawCurrentMah: info.rawCurrentCapacityMah,
                rawMaxMah: info.rawMaxCapacityMah
            )
        } else if !info.isPluggedIn {
            info.timeRemainingMinutes = estimateTimeRemaining(
                currentPercentage: info.percentage,
                rawCurrentMah: info.rawCurrentCapacityMah
            )
        }

        DispatchQueue.main.async {
            self.batteryInfo = info
        }
    }

    // MARK: - Percentage history

    private func recordPercentage(_ percentage: Int) {
        let now = Date()

        // Only record when the percentage actually changes.
        if let last = percentageSamples.last, last.percentage == percentage { return }

        percentageSamples.append((date: now, percentage: percentage))
        lastPercentageChangeDate = now

        // Recompute rate from full history.
        guard percentageSamples.count >= 2,
              let first = percentageSamples.first else { return }

        let totalChange = abs(Double(first.percentage - percentage))
        let totalMinutes = now.timeIntervalSince(first.date) / 60.0

        guard totalChange > 0, totalMinutes > 0 else { return }
        historicalRatePerMinute = totalChange / totalMinutes
    }

    // MARK: - Time estimates

    /// Time remaining on battery. Uses percentage history when available,
    /// falls back to smoothed amperage (with real mAh) for the first few minutes.
    private func estimateTimeRemaining(currentPercentage: Int, rawCurrentMah: Int) -> Int? {
        if let rate = historicalRatePerMinute, rate > 0 {
            let minutesFromPercentage = Double(currentPercentage) / rate
            let elapsed = Date().timeIntervalSince(lastPercentageChangeDate) / 60.0
            return max(0, Int(minutesFromPercentage - elapsed))
        }

        // Fallback: mAh / mA = hours
        guard smoothedAmperage > 0, rawCurrentMah > 0 else { return nil }
        return max(0, Int(Double(rawCurrentMah) / smoothedAmperage * 60))
    }

    /// Time until full charge. Same dual strategy.
    private func estimateTimeToFull(currentPercentage: Int, rawCurrentMah: Int, rawMaxMah: Int) -> Int? {
        if let rate = historicalRatePerMinute, rate > 0 {
            let remaining = Double(100 - currentPercentage)
            let minutesFromPercentage = remaining / rate
            let elapsed = Date().timeIntervalSince(lastPercentageChangeDate) / 60.0
            return max(0, Int(minutesFromPercentage - elapsed))
        }

        let remainingMah = Double(rawMaxMah - rawCurrentMah)
        guard smoothedAmperage > 0, remainingMah > 0 else { return nil }
        return max(0, Int(remainingMah / smoothedAmperage * 60))
    }

    // MARK: - Amperage EMA (fallback)

    private func updateSmoothedAmperage(_ rawAmperage: Double) {
        guard rawAmperage > 0 else { return }
        if smoothedAmperage == 0 {
            smoothedAmperage = rawAmperage
        } else {
            smoothedAmperage = emaAlpha * rawAmperage + (1 - emaAlpha) * smoothedAmperage
        }
    }

    // MARK: - Lifecycle

    private func resetHistory() {
        percentageSamples.removeAll()
        historicalRatePerMinute = nil
        smoothedAmperage = 0
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    private func observePowerSourceChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.update()
        }, context)?.takeRetainedValue() {
            powerSourceLoop = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func observeSleepWake() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.resetHistory()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self?.update()
                }
            }
            .store(in: &cancellables)
    }
}
