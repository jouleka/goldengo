# Goldengo Plan 3d — Lock-Screen Reveal Toggle (GOL-35)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Close GOL-35 — let the user opt into showing widget amounts on the Lock Screen. Default is redacted (privacy-first, spec §11); a Settings toggle flips it.

**Architecture:** A `revealOnLockScreen` flag in the App Group `UserDefaults` (`SharedSummary`), set by a new **Settings** tab (SwiftUI `Toggle` via `@AppStorage` on the App Group store) and read by the widget, which applies `.privacySensitive(!reveal)`. The flag is independent of the today-total write (logging must not reset it).

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, App Groups. Xcode 26.5, iPhone 17 simulator.

---

### Task 1: `revealOnLockScreen` flag in `SharedSummary` (independent of the total)

**Files:**
- Modify: `Sources/GoldengoData/SharedSummary.swift`
- Modify: `Sources/GoldengoData/IngestionStore.swift` (write only the total)
- Test: `Tests/GoldengoDataTests/SharedSummaryTests.swift`

- [ ] **Step 1: Update the failing test** — replace the body of `SharedSummaryTests` with:
```swift
import XCTest
@testable import GoldengoData

final class SharedSummaryTests: XCTestCase {
    private func freshSuite() -> String { "test.goldengo.\(UUID().uuidString)" }

    func test_total_roundTrips() {
        let s = SharedSummary(suiteName: freshSuite())
        s.writeTodayTotal("L 1,234")
        XCTAssertEqual(s.read().todayTotalText, "L 1,234")
    }

    func test_reveal_defaultsFalse_andRoundTrips() {
        let s = SharedSummary(suiteName: freshSuite())
        XCTAssertFalse(s.read().revealOnLockScreen)       // private by default
        s.setRevealOnLockScreen(true)
        XCTAssertTrue(s.read().revealOnLockScreen)
    }

    func test_writingTotal_doesNotResetReveal() {
        let s = SharedSummary(suiteName: freshSuite())
        s.setRevealOnLockScreen(true)
        s.writeTodayTotal("L 99")                          // logging must not clobber the pref
        XCTAssertTrue(s.read().revealOnLockScreen)
    }
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter SharedSummaryTests` → FAIL.

- [ ] **Step 3: Rewrite `SharedSummary`**
```swift
import Foundation

public struct SharedSummary {
    public struct Snapshot: Equatable {
        public var todayTotalText: String
        public var revealOnLockScreen: Bool
    }
    private let defaults: UserDefaults
    public static let appGroupID = "group.com.goldengo.app"
    public static let revealKey = "revealOnLockScreen"
    private static let totalKey = "todayTotalText"

    public init(suiteName: String? = SharedSummary.appGroupID) {
        defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func writeTodayTotal(_ text: String) { defaults.set(text, forKey: Self.totalKey) }
    public func setRevealOnLockScreen(_ on: Bool) { defaults.set(on, forKey: Self.revealKey) }

    public func read() -> Snapshot {
        Snapshot(todayTotalText: defaults.string(forKey: Self.totalKey) ?? "—",
                 revealOnLockScreen: defaults.bool(forKey: Self.revealKey))
    }
}
```

- [ ] **Step 4: Update `IngestionStore.logManual`** — change the summary write to:
```swift
        SharedSummary().writeTodayTotal(Money(amount: total, currency: currency).formatted())
```
(remove the old `write(todayTotalText:redacted:)` call).

- [ ] **Step 5: Run** — `swift test --filter SharedSummaryTests` → PASS; full `swift test` → green.

- [ ] **Step 6: Commit**
```bash
git add Sources/GoldengoData/SharedSummary.swift Sources/GoldengoData/IngestionStore.swift Tests/GoldengoDataTests/SharedSummaryTests.swift
git commit -m "feat: add revealOnLockScreen flag in SharedSummary, independent of the total (GOL-35)"
```

---

### Task 2: Widget honors the reveal flag

**Files:**
- Modify: `AppProject/Widget/GoldengoWidget.swift`

- [ ] **Step 1: Read the flag and apply it** — give `GoldengoEntry` a `reveal` field and set it from `SharedSummary().read().revealOnLockScreen` in the provider's `getSnapshot`/`getTimeline`/`placeholder`. Then change the amount line from `.privacySensitive()` to:
```swift
            Text(entry.totalText).font(.title2.bold()).minimumScaleFactor(0.6)
                .privacySensitive(!entry.reveal)   // redacted on Lock Screen unless the user opted in
```

- [ ] **Step 2: Build** — `ruby AppProject/project.rb` then `xcodebuild ... build` → `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**
```bash
git add AppProject/Widget/GoldengoWidget.swift AppProject/Goldengo.xcodeproj/project.pbxproj
git commit -m "feat: widget redacts amounts on Lock Screen unless reveal is on (GOL-35)"
```

---

### Task 3: Settings tab with the toggle

**Files:**
- Create: `Sources/GoldengoFeatures/Settings/SettingsView.swift`
- Modify: `Sources/GoldengoFeatures/RootView.swift` (add a Settings tab + deep-link case)

- [ ] **Step 1: Implement the Settings view** (binds directly to the App Group default the widget reads)
```swift
import SwiftUI
import GoldengoData

public struct SettingsView: View {
    @AppStorage(SharedSummary.revealKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var reveal: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    Toggle("Show amounts on Lock Screen", isOn: $reveal)
                    Text("Off by default — your spending stays hidden on the Lock Screen widget.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

- [ ] **Step 2: Add the Settings tab** — in `RootView.body`, add after the Recent tab:
```swift
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
```
And add a deep-link case in `tab(forDeepLink:)`: `case "settings": return 2`.

- [ ] **Step 3: Build, run, screenshot, verify** — build + launch, switch to the **Settings** tab, screenshot `AppProject/.build/settings.png`, read it, confirm the "Show amounts on Lock Screen" toggle renders (off by default). `swift test` → green (existing `RootViewRoutingTests` still pass; optionally add `goldengo://settings` → 2).

- [ ] **Step 4: Commit**
```bash
git add Sources/GoldengoFeatures/Settings Sources/GoldengoFeatures/RootView.swift Tests/GoldengoFeaturesTests/RootViewRoutingTests.swift
git commit -m "feat: add Settings tab with lock-screen reveal toggle (GOL-35)"
```

---

## Done criteria
- `swift test` green (SharedSummary reveal round-trip + independence).
- App builds + the **Settings tab** renders the toggle in the simulator (screenshot-verified), off by default.
- Widget applies `.privacySensitive(!reveal)`; logging the total never resets the pref.
- Closes GOL-35.
