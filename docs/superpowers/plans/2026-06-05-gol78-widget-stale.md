# Widget stale-data fix (GOL-78) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the home-screen widget showing yesterday's total — date-stamp the cached today-total (show it only if it's from today, else 0), roll over at midnight, and reload the widget on every log (incl. the Apple Pay automation).

**Architecture:** All display logic lives in one testable `SharedSummary.todayDisplayText(now:)` helper (date-aware); the widget routes placeholder/snapshot/timeline through it (so it needs no `GoldengoCore`/`Money` import), and supplies a `now` + `nextMidnight` entry so it rolls to 0 on its own. The widget reload moves into `refreshSharedTodayTotal` so every save path refreshes it.

**Tech Stack:** Swift 6, WidgetKit, SwiftData, XCTest. `swift test` (also macOS CI) for the `SharedSummary` logic; `xcodebuild` for the widget target / device.

**Branch:** `feature/gol-78-widget-stale` (created; spec committed).

---

## File structure

**Modify (Sources):**
- `Sources/GoldengoData/SharedSummary.swift` — date-stamp the total + `todayDisplayText(now:)`
- `Sources/GoldengoData/IngestionStore.swift` — `refreshSharedTodayTotal` reloads the widget (guarded)
- `AppProject/Widget/GoldengoWidget.swift` — date-aware display + midnight rollover + placeholder fix

**Modify (Tests):** `Tests/GoldengoDataTests/SharedSummaryTests.swift` — date-aware display tests.

No `project.rb` change; no persistence/model change. Existing in-app `reloadAllTimelines()` calls (`QuickAddModel`, `ImportModel`) are left as-is (now redundant but benign — iOS coalesces).

---

## Task 1: `SharedSummary` — date-stamp + `todayDisplayText` (TDD)

**Files:**
- Modify: `Sources/GoldengoData/SharedSummary.swift`
- Test: `Tests/GoldengoDataTests/SharedSummaryTests.swift`

- [ ] **Step 1: Write the failing tests**

Add inside `SharedSummaryTests` (before the closing brace):

```swift
    func test_todayDisplayText_showsCachedTotal_whenStampedToday() {
        let s = SharedSummary(suiteName: freshSuite())
        let now = Date()
        s.writeTodayTotal("ALL 500", asOf: now)
        XCTAssertEqual(s.todayDisplayText(now: now), "ALL 500")
    }

    func test_todayDisplayText_showsZero_whenStampedAPreviousDay() {
        // The bug: a total computed yesterday must not show as today's — a new day reads 0.
        let s = SharedSummary(suiteName: freshSuite())
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        s.writeTodayTotal("ALL 500", asOf: yesterday)
        XCTAssertEqual(s.todayDisplayText(now: today), "ALL 0")   // lek = 0 decimals
    }

    func test_todayDisplayText_showsZero_whenNeverWritten() {
        let s = SharedSummary(suiteName: freshSuite())
        XCTAssertEqual(s.todayDisplayText(), "ALL 0")             // default preferred currency = lek
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SharedSummaryTests`
Expected: FAIL — compile error (`extra argument 'asOf'` / no member `todayDisplayText`).

- [ ] **Step 3: Implement the date-stamp + accessor**

In `SharedSummary.swift`, add the date key next to `totalKey`:

```swift
    private static let totalKey = "todayTotalText"
    private static let totalDateKey = "todayTotalDate"
```

Replace `writeTodayTotal` (currently `public func writeTodayTotal(_ text: String) { defaults.set(text, forKey: Self.totalKey) }`):

```swift
    public func writeTodayTotal(_ text: String, asOf date: Date = .now) {
        defaults.set(text, forKey: Self.totalKey)
        defaults.set(date, forKey: Self.totalDateKey)
    }
```

Add the date-aware accessor (e.g. after `read()`):

```swift
    /// The total to show *for today*: the cached value if it was computed today, otherwise zero in the
    /// preferred currency (a new day with nothing logged yet — or never written). The widget uses this
    /// so it never shows a previous day's total.
    public func todayDisplayText(now: Date = .now) -> String {
        if let text = defaults.string(forKey: Self.totalKey),
           let date = defaults.object(forKey: Self.totalDateKey) as? Date,
           Calendar.current.isDate(date, inSameDayAs: now) {
            return text
        }
        return Money(amount: 0, currency: readPreferredCurrency()).formatted()
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SharedSummaryTests`
Expected: PASS (all `SharedSummaryTests`, including the 3 new ones; the existing `test_total_roundTrips` still passes — `asOf` defaults).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/SharedSummary.swift Tests/GoldengoDataTests/SharedSummaryTests.swift
git commit -m "feat(gol-78): date-stamp the shared today-total; todayDisplayText shows 0 on a new day"
```

---

## Task 2: `refreshSharedTodayTotal` reloads the widget (GoldengoData)

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift`

No unit test (the reload is OS-side + guarded off on macOS; the date-write is covered by Task 1).

- [ ] **Step 1: Import WidgetKit (guarded) at the top of `IngestionStore.swift`**

After the existing imports (`import Foundation` / `import SwiftData` / `import GoldengoCore`):

```swift
#if canImport(WidgetKit)
import WidgetKit
#endif
```

- [ ] **Step 2: Reload the widget after writing the total**

In `refreshSharedTodayTotal()` (`IngestionStore.swift:91-96`), after the `writeTodayTotal(...)` line, add:

```swift
        SharedSummary().writeTodayTotal(Money(amount: total, currency: display).formatted())
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()   // every save path (incl. the Apple Pay automation) refreshes the widget
#endif
```

(`writeTodayTotal` now stamps today's date via its `asOf` default, so no change to this call beyond the reload.)

- [ ] **Step 3: Build to verify the guard compiles (macOS/CI surface)**

Run: `swift build`
Expected: succeeds (on macOS `canImport(WidgetKit)` is false, so the import + call compile out — keeping `swift test`/CI green).

- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoData/IngestionStore.swift
git commit -m "feat(gol-78): refreshSharedTodayTotal reloads the widget on every total change"
```

---

## Task 3: Widget — date-aware display + midnight rollover (`GoldengoWidget.swift`)

**Files:**
- Modify: `AppProject/Widget/GoldengoWidget.swift`

No unit test (widget target isn't in `swift test`; timelines are OS-driven — verified by build + device).

- [ ] **Step 1: Replace the `GoldengoProvider` body**

Replace the `GoldengoProvider` struct (`GoldengoWidget.swift:8-21`) with:

```swift
struct GoldengoProvider: TimelineProvider {
    func placeholder(in c: Context) -> GoldengoEntry {
        .init(date: .now, totalText: SharedSummary().todayDisplayText(), reveal: false)
    }
    func getSnapshot(in c: Context, completion: @escaping (GoldengoEntry) -> Void) {
        let s = SharedSummary()
        completion(.init(date: .now, totalText: s.todayDisplayText(), reveal: s.read().revealOnLockScreen))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<GoldengoEntry>) -> Void) {
        let s = SharedSummary()
        let reveal = s.read().revealOnLockScreen
        let now = Date.now
        let midnight = Calendar.current.nextDate(after: now,
                                                 matching: DateComponents(hour: 0, minute: 0, second: 0),
                                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        // Two entries: today's total now, and 0 at midnight (the cache's date is no longer "today" by
        // then, so todayDisplayText returns 0) — so it rolls over even without an exact-midnight refresh.
        let entries = [
            GoldengoEntry(date: now, totalText: s.todayDisplayText(now: now), reveal: reveal),
            GoldengoEntry(date: midnight, totalText: s.todayDisplayText(now: midnight), reveal: reveal),
        ]
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}
```

(This removes the hardcoded `"L 0"` placeholder and the raw `todayTotalText` reads, replacing both with the date-aware `todayDisplayText`. No new import — `todayDisplayText` returns the formatted string from `GoldengoData`.)

- [ ] **Step 2: Build for the iOS simulator**

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED (the widget target compiles with the `SharedSummary.todayDisplayText` usage).

- [ ] **Step 3: Commit**

```bash
git add AppProject/Widget/GoldengoWidget.swift
git commit -m "feat(gol-78): widget shows today-only total via todayDisplayText + rolls over at midnight"
```

---

## Task 4: Full verification, device, review, handoff

- [ ] **Step 1: Full test suite green**

Run: `swift test`
Expected: all pass (baseline + the 3 new `SharedSummaryTests`), zero skipped.

- [ ] **Step 2: Device build + install**

```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath AppProject/.build-device build
xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E AppProject/.build-device/Build/Products/Debug-iphoneos/Goldengo.app
```
Expected: BUILD SUCCEEDED + `App installed`. (If it errors "device locked," ask the user to unlock and retry the install.)

- [ ] **Step 3: On-device check (user)**

Ask the user: confirm the widget now shows **today's** total (not yesterday's); add an expense in-app → the widget updates within a moment; (optionally) tap-pay via the Apple Pay automation → the widget updates. The midnight rollover can't be forced on demand, but the date-stamp tests cover that logic.

- [ ] **Step 4: Second-Opus review**

Dispatch a fresh general-purpose reviewer (model: opus) over `git diff main...HEAD`; fix real findings, re-run `swift test`.

- [ ] **Step 5: Merge + ticket**

On the user's go: `git checkout main && git merge --ff-only feature/gol-78-widget-stale && git push`. Set GOL-78 → **To Verify** with a summary comment.

---

## Self-review

**Spec coverage** (against `2026-06-05-gol78-widget-stale-design.md`):
- §Component 1 (date-stamp + `todayDisplayText`) → Task 1. ✓
- §Component 2 (`refreshSharedTodayTotal` reloads, guarded) → Task 2. ✓
- §Component 3 (widget date-aware + midnight rollover + placeholder fix) → Task 3. ✓
- §Tests (today→text, yesterday→0, never→0) → Task 1. ✓
- §Data flow + runtime verification → Tasks 2/3/4. ✓
- §Out of scope (no DB recompute, no new in-app reloads removed) → honored. ✓

**Placeholder scan:** none — every code step is complete; commands have expected output.

**Type consistency:** `writeTodayTotal(_:asOf:)` (asOf defaulted) and `todayDisplayText(now:)` are defined in Task 1 and used identically in Task 2 (the defaulted `asOf` via the existing call) and Task 3 (the widget). `GoldengoEntry(date:totalText:reveal:)` matches the existing struct (`GoldengoWidget.swift:6`). `SharedSummary().read().revealOnLockScreen` and `readPreferredCurrency()` are existing APIs. `Money(amount:currency:).formatted()` is used only inside `SharedSummary` (which imports `GoldengoCore`), so the widget needs no new import.
