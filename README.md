# BatteryBuddy

A native macOS menu bar app that shows battery status, per-app energy usage, and actionable insights. Built with Swift/SwiftUI, no external dependencies.

## What it does

**Menu bar** shows battery percentage and time remaining in compact format:
- On battery: `🔋 85% - 6:21`
- Charging: `⚡ 86% - 1:23`
- Full: `⚡ 100% — Charged`

**Click to open** a dropdown with:
- Battery percentage, health, power draw (watts), and time estimate
- Top 10 processes ranked by energy impact with app icons
- Quick insights like "If you closed Chrome, you'd gain ~1h 20m"

**Notifications** for low battery (<20%), sudden energy spikes, and unusually high drain — with 30-minute cooldowns so they're not spammy.

## How it works

- **Battery data** comes from IOKit's `AppleSmartBattery` registry (voltage, amperage, capacity in mAh, cycle count, etc.)
- **Time estimates** use a dual strategy: a percentage-history approach that gets more accurate the longer the app runs (averaging across all observed percentage drops), with an amperage-based EMA as a fallback for the first few minutes
- **Per-process energy** is estimated by running `ps` every 30 seconds, grouping child processes under their parent app bundle, and attributing CPU-proportional power after subtracting ~6W base system overhead (display, RAM, Wi-Fi, etc.)
- **Plug/unplug detection** is instant via `IOPSNotificationCreateRunLoopSource` — no waiting for the 30-second poll
- **Sleep/wake** resets all drain history since the data is stale after sleep

## Build & run

Requires macOS 15+ (Sequoia) on Apple Silicon.

**From terminal** (no Xcode needed):
```sh
./build.sh
open build/BatteryBuddy.app
```

**From Xcode:**
```sh
open BatteryBuddy.xcodeproj
```
Then Cmd+R.

## Project structure

```
BatteryBuddy/
├── App/BatteryBuddyApp.swift          # Entry point, MenuBarExtra setup
├── Models/
│   ├── BatteryInfo.swift               # Battery state struct
│   └── ProcessInfo.swift               # Per-app energy data struct
├── Services/
│   ├── BatteryMonitor.swift            # IOKit battery polling + time estimates
│   ├── ProcessMonitor.swift            # ps-based process energy tracking
│   └── NotificationManager.swift       # macOS notifications with cooldowns
├── Views/
│   ├── StatusItemView.swift            # Menu bar label (icon + text)
│   ├── MenuBarView.swift               # Dropdown panel layout
│   └── ProcessListView.swift           # Energy-ranked process list
├── Utilities/Extensions.swift          # PID path resolution, formatting helpers
└── Resources/
    ├── Info.plist                       # LSUIElement=true (no dock icon)
    ├── BatteryBuddy.entitlements        # No sandbox
    └── Assets.xcassets/
```

## Key design decisions

- **No sandbox, no code signing** — runs locally with ad-hoc signing (`-`). The build script handles `xattr -cr` and `codesign --force --deep --sign -` automatically.
- **LSUIElement=true** — menu bar only, no dock icon, no main window.
- **Apple Silicon IOKit keys** — uses `AppleRawCurrentCapacity` / `AppleRawMaxCapacity` for actual mAh values, since `CurrentCapacity` / `MaxCapacity` report percentages on M-series chips.
- **Pipe read before wait** — `ps -A` output is read before `waitUntilExit()` to avoid pipe buffer deadlocks.

## Maintaining

**Adding a new known process name:** Edit the `knownProcessNames` dictionary in `ProcessMonitor.swift` (bottom of file). Maps raw process names like `"mds_stores"` to human-readable names like `"Spotlight"`.

**Adjusting base system power overhead:** Change `baseSystemWatts` in `ProcessMonitor.swift` (default 6W). Higher = lower per-app watt estimates. This affects the watt display, not the "time you'd gain" insights.

**Tuning time estimate smoothing:** The amperage EMA alpha is `0.15` in `BatteryMonitor.swift`. Lower = smoother but slower to react. The percentage-history approach dominates after the first percentage drop anyway.

**Notification thresholds:** In `NotificationManager.swift` — low battery triggers at 20%, cooldown is 30 minutes, spike detection requires >20% CPU jump with >20% time drop.

**Poll interval:** Both monitors use 30-second timers. Plug/unplug events are instant via IOKit callback regardless of timer.
