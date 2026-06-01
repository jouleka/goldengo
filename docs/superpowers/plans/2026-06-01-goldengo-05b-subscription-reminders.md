# Subscription Reminders Implementation Plan (GOL-60)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send a local notification a configurable number of days before a **confirmed** subscription's predicted next charge, opt-in via a Settings toggle.

**Architecture:** A **pure planner** in `GoldengoCore` decides which reminders fire and when. A pure mapping in `GoldengoFeatures` turns confirmed `SubscriptionSnapshot`s into reminder inputs. A thin `LocalNotificationScheduler` (UNUserNotificationCenter) is the only non-testable glue. The Settings toggle requests permission; `SubscriptionsModel.load()` keeps the schedule in sync with the current confirmed set.

**Tech Stack:** Swift 6, SwiftUI, `UNUserNotificationCenter`, `@AppStorage` over the App Group `UserDefaults`.

**Branch:** `gol-60-reminders` (created before execution; do NOT implement on `main`).

**Commit convention (workspace rule):** Do **NOT** add a `Co-Authored-By: Claude` trailer. Conventional-commit style.

**Product rules:**
- Reminders fire ONLY for **confirmed** subscriptions (`isConfirmed == true`) — never for mere candidates; the user opts in per-subscription by confirming, and globally via the Settings toggle.
- Off by default. Enabling the toggle requests notification authorization; disabling cancels all our pending reminders.
- Local notifications need NO Info.plist usage-description key (authorization is requested at runtime).
- Reminders stay in sync: every `SubscriptionsModel.load()` (on appear / pull-to-refresh / after confirm/dismiss) re-syncs the scheduled set when the toggle is on.

---

## File Structure

**Create:**
- `Sources/GoldengoCore/SubscriptionReminderPlanner.swift` — pure planner (`ReminderInput`, `ReminderRequest`, `plan`).
- `Tests/GoldengoCoreTests/SubscriptionReminderPlannerTests.swift`
- `Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift` — pure `inputs(from:)` mapping + `LocalNotificationScheduler` glue.
- `Tests/GoldengoFeaturesTests/SubscriptionRemindersTests.swift` — tests the pure mapping.

**Modify:**
- `Sources/GoldengoData/SharedSummary.swift` — add `remindBeforeChargesKey`, `reminderLeadDaysKey` constants.
- `Sources/GoldengoFeatures/Subscriptions/SubscriptionsModel.swift` — re-sync reminders at the end of `load()`.
- `Sources/GoldengoFeatures/Settings/SettingsView.swift` — add the toggle + days-before stepper; request/cancel authorization on change.

---

## Task 1: Pure reminder planner (`GoldengoCore`)

**Files:**
- Create: `Sources/GoldengoCore/SubscriptionReminderPlanner.swift`
- Test: `Tests/GoldengoCoreTests/SubscriptionReminderPlannerTests.swift`

- [ ] **Step 1: Write the failing tests** — create `Tests/GoldengoCoreTests/SubscriptionReminderPlannerTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class SubscriptionReminderPlannerTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
    private func input(_ id: String, _ next: Date) -> SubscriptionReminderPlanner.ReminderInput {
        .init(id: id, title: "T", body: "B", nextCharge: next)
    }

    func test_firesLeadDaysBeforeNextCharge() {
        let out = SubscriptionReminderPlanner.plan([input("x", day(2026, 4, 5))],
                                                   leadDays: 1, now: day(2026, 3, 1), calendar: cal)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: out[0].fireDate),
                       cal.dateComponents([.year, .month, .day], from: day(2026, 4, 4)))
        XCTAssertEqual(out[0].id, "x")
    }

    func test_skipsRemindersWhoseFireDateIsPast() {
        let out = SubscriptionReminderPlanner.plan([input("x", day(2026, 1, 1))],
                                                   leadDays: 1, now: day(2026, 3, 1), calendar: cal)
        XCTAssertTrue(out.isEmpty)   // fire date Dec 31 is before now
    }

    func test_leadZeroFiresOnChargeDay() {
        let out = SubscriptionReminderPlanner.plan([input("x", day(2026, 4, 5))],
                                                   leadDays: 0, now: day(2026, 3, 1), calendar: cal)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: out[0].fireDate),
                       cal.dateComponents([.year, .month, .day], from: day(2026, 4, 5)))
    }

    func test_multipleInputs_preservedAndFiltered() {
        let out = SubscriptionReminderPlanner.plan(
            [input("future", day(2026, 5, 10)), input("past", day(2026, 1, 1))],
            leadDays: 2, now: day(2026, 3, 1), calendar: cal)
        XCTAssertEqual(out.map(\.id), ["future"])
    }

    func test_empty() {
        XCTAssertTrue(SubscriptionReminderPlanner.plan([], leadDays: 1, now: day(2026, 3, 1), calendar: cal).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify they FAIL** — Run: `swift test --filter GoldengoCoreTests.SubscriptionReminderPlannerTests` → FAIL (type not defined).

- [ ] **Step 3: Implement** — create `Sources/GoldengoCore/SubscriptionReminderPlanner.swift`:

```swift
import Foundation

/// Pure logic for WHICH subscription reminders to schedule and WHEN. The OS scheduling glue lives
/// in the Features layer (`LocalNotificationScheduler`); this stays trivially unit-testable.
public enum SubscriptionReminderPlanner {
    public struct ReminderInput: Sendable, Equatable {
        public var id: String          // subscription matchKey
        public var title: String
        public var body: String
        public var nextCharge: Date
        public init(id: String, title: String, body: String, nextCharge: Date) {
            self.id = id; self.title = title; self.body = body; self.nextCharge = nextCharge
        }
    }
    public struct ReminderRequest: Sendable, Equatable {
        public var id: String
        public var title: String
        public var body: String
        public var fireDate: Date
        public init(id: String, title: String, body: String, fireDate: Date) {
            self.id = id; self.title = title; self.body = body; self.fireDate = fireDate
        }
    }

    /// Fire `leadDays` before each next-charge, dropping any whose fire date is already before `now`.
    /// Works off the START OF the charge's day (in `calendar`) so the result is a clean day boundary:
    /// `nextCharge`'s time-of-day traces back to a raw transaction timestamp under a UTC calendar, and
    /// carrying it would risk firing at an odd local hour or rolling to an adjacent local day. The
    /// scheduler pins the fire hour (09:00 local); here we only care about the correct day.
    public static func plan(_ inputs: [ReminderInput], leadDays: Int, now: Date,
                            calendar: Calendar) -> [ReminderRequest] {
        inputs.compactMap { input in
            let chargeDay = calendar.startOfDay(for: input.nextCharge)
            guard let fire = calendar.date(byAdding: .day, value: -leadDays, to: chargeDay),
                  fire >= now else { return nil }
            return ReminderRequest(id: input.id, title: input.title, body: input.body, fireDate: fire)
        }
    }
}
```

- [ ] **Step 4: Run to verify PASS** — Run: `swift test --filter GoldengoCoreTests.SubscriptionReminderPlannerTests` → PASS (5 tests). Then `swift test --filter GoldengoCoreTests` → PASS (no regressions).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/SubscriptionReminderPlanner.swift Tests/GoldengoCoreTests/SubscriptionReminderPlannerTests.swift
git commit -m "feat: pure subscription reminder planner (lead-days before next charge, drops past)"
```

---

## Task 2: Settings keys + reminder-input mapping + notification scheduler

**Files:**
- Modify: `Sources/GoldengoData/SharedSummary.swift`
- Create: `Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift`
- Test: `Tests/GoldengoFeaturesTests/SubscriptionRemindersTests.swift`

> **Context:** `SubscriptionSnapshot` (in `GoldengoData`) has: `id` (matchKey), `displayName`, `amount: Decimal`, `currencyCode: String`, `cadence`, `nextChargeDate: Date`, `occurrenceCount`, `confidence`, `isVariableAmount`, `hadTrial`, `isConfirmed`. `Money(amount:currency:).formatted()` (in `GoldengoCore`) renders amounts. `GoldengoFeatures` already imports `GoldengoCore` and `GoldengoData`.

- [ ] **Step 1: Add the settings keys** — in `Sources/GoldengoData/SharedSummary.swift`, alongside the existing `revealKey`, add:

```swift
    public static let remindBeforeChargesKey = "remindBeforeCharges"
    public static let reminderLeadDaysKey = "reminderLeadDays"
```

- [ ] **Step 2: Write the failing test** — create `Tests/GoldengoFeaturesTests/SubscriptionRemindersTests.swift`:

```swift
import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

final class SubscriptionRemindersTests: XCTestCase {
    private func snap(_ id: String, _ name: String, confirmed: Bool) -> SubscriptionSnapshot {
        SubscriptionSnapshot(id: id, displayName: name, amount: 1200, currencyCode: "ALL",
                             cadence: .monthly, nextChargeDate: Date(timeIntervalSince1970: 1_800_000_000),
                             occurrenceCount: 3, confidence: 0.8, isVariableAmount: false,
                             hadTrial: false, isConfirmed: confirmed)
    }

    func test_inputs_onlyFromConfirmed() {
        let inputs = SubscriptionReminders.inputs(from: [
            snap("a|monthly|ALL", "Netflix", confirmed: true),
            snap("b|monthly|ALL", "Spotify", confirmed: false),
        ])
        XCTAssertEqual(inputs.map(\.id), ["a|monthly|ALL"])
        XCTAssertTrue(inputs[0].title.contains("Netflix"))
        XCTAssertFalse(inputs[0].body.isEmpty)
        XCTAssertEqual(inputs[0].nextCharge, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func test_inputs_emptyWhenNoneConfirmed() {
        XCTAssertTrue(SubscriptionReminders.inputs(from: [snap("a", "X", confirmed: false)]).isEmpty)
    }

    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private var pastNow: Date { Date(timeIntervalSince1970: 1_700_000_000) }   // ~2023, before snap nextCharge (~2027)

    func test_plannedRequests_disabled_returnsEmpty() {
        let cands = [snap("a", "Netflix", confirmed: true)]
        XCTAssertTrue(SubscriptionReminders.plannedRequests(
            enabled: false, leadDays: 1, candidates: cands, now: pastNow, calendar: utc).isEmpty)
    }

    func test_plannedRequests_clampsUnsetLeadDaysToOne() {
        // UserDefaults.integer returns 0 when the key is unset; plannedRequests must clamp to 1.
        let cands = [snap("a", "Netflix", confirmed: true)]
        let zero = SubscriptionReminders.plannedRequests(enabled: true, leadDays: 0, candidates: cands, now: pastNow, calendar: utc)
        let one = SubscriptionReminders.plannedRequests(enabled: true, leadDays: 1, candidates: cands, now: pastNow, calendar: utc)
        XCTAssertEqual(zero, one)
        XCTAssertEqual(zero.count, 1)
    }

    func test_plannedRequests_onlyConfirmed() {
        let cands = [snap("a", "Netflix", confirmed: true), snap("b", "Spotify", confirmed: false)]
        let reqs = SubscriptionReminders.plannedRequests(enabled: true, leadDays: 1, candidates: cands, now: pastNow, calendar: utc)
        XCTAssertEqual(reqs.map(\.id), ["a"])
    }
}
```

- [ ] **Step 3: Run to verify it FAILS** — Run: `swift test --filter GoldengoFeaturesTests.SubscriptionRemindersTests` → FAIL.

- [ ] **Step 4: Implement** — create `Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift`:

```swift
import Foundation
import GoldengoCore
import GoldengoData
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Pure mapping from confirmed subscription snapshots to reminder inputs.
public enum SubscriptionReminders {
    /// Build reminder inputs from CONFIRMED candidates only (the user opted in by confirming).
    public static func inputs(from candidates: [SubscriptionSnapshot]) -> [SubscriptionReminderPlanner.ReminderInput] {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        return candidates.filter { $0.isConfirmed }.map { s in
            let money = Money(amount: s.amount, currency: CurrencyCode(s.currencyCode)).formatted()
            return SubscriptionReminderPlanner.ReminderInput(
                id: s.id,
                title: "\(s.displayName) renews soon",
                body: "About \(money) on \(df.string(from: s.nextChargeDate)).",
                nextCharge: s.nextChargeDate)
        }
    }

    /// The full, pure decision the UI needs: returns the reminders to schedule given the toggle state
    /// and stored lead-days. Returns [] when disabled (so the caller's `sync([])` clears any stale
    /// reminders — self-healing). `leadDays` is clamped to >= 1: `UserDefaults.integer` yields 0 when
    /// the key is unset, which must coincide with the @AppStorage default (1) and the stepper min (1).
    public static func plannedRequests(enabled: Bool, leadDays: Int, candidates: [SubscriptionSnapshot],
                                       now: Date, calendar: Calendar) -> [SubscriptionReminderPlanner.ReminderRequest] {
        guard enabled else { return [] }
        return SubscriptionReminderPlanner.plan(inputs(from: candidates),
                                                leadDays: max(1, leadDays), now: now, calendar: calendar)
    }
}

/// Thin glue over `UNUserNotificationCenter`. All decision logic is in `SubscriptionReminderPlanner`
/// / `SubscriptionReminders` (pure, tested); this only requests authorization and registers requests.
public enum LocalNotificationScheduler {
    private static let prefix = "sub-reminder:"

    /// Requests authorization (alert + sound). Returns whether granted. No-op off-device.
    @discardableResult
    public static func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        #else
        return false
        #endif
    }

    /// Replace our pending subscription reminders with exactly `requests` (idempotent re-sync).
    public static func sync(_ requests: [SubscriptionReminderPlanner.ReminderRequest]) async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        for r in requests {
            let content = UNMutableNotificationContent()
            content.title = r.title; content.body = r.body; content.sound = .default
            // Fire at 09:00 local on the planner-computed day. We take ONLY the day from fireDate and
            // pin a sane hour — the planner already did the "N days before" math on a day boundary.
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: r.fireDate)
            comps.hour = 9; comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + r.id, content: content, trigger: trigger))
        }
        #endif
    }

    /// Cancel all of our pending subscription reminders.
    public static func cancelAll() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        #endif
    }
}
```

- [ ] **Step 5: Run to verify PASS** — Run: `swift test --filter GoldengoFeaturesTests.SubscriptionRemindersTests` → PASS. Then `swift build` → clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoData/SharedSummary.swift Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift Tests/GoldengoFeaturesTests/SubscriptionRemindersTests.swift
git commit -m "feat: confirmed-subscription reminder mapping + thin UNUserNotificationCenter scheduler"
```

---

## Task 3: Settings toggle + wire into Subscriptions

**Files:**
- Modify: `Sources/GoldengoFeatures/Settings/SettingsView.swift`
- Modify: `Sources/GoldengoFeatures/Subscriptions/SubscriptionsModel.swift`

> **Context:** `SettingsView` already uses `@AppStorage(key, store: UserDefaults(suiteName: SharedSummary.appGroupID))` for the lock-screen toggle. `SubscriptionsModel.load()` currently does: guard `!isLoading`, set loading, `refreshSubscriptions()`, set `rows`. Add reminder sync at the end of `load()`.

- [ ] **Step 1: Add the Settings toggle** — in `Sources/GoldengoFeatures/Settings/SettingsView.swift`, add the import and the new `@AppStorage` properties + section. Full new file:

```swift
import SwiftUI
import GoldengoData

public struct SettingsView: View {
    @AppStorage(SharedSummary.revealKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var reveal: Bool = false
    @AppStorage(SharedSummary.remindBeforeChargesKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var remind: Bool = false
    @AppStorage(SharedSummary.reminderLeadDaysKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var leadDays: Int = 1

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    Toggle("Show amounts on Lock Screen", isOn: $reveal)
                    Text("Off by default — your spending stays hidden on the Lock Screen widget.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Subscriptions") {
                    Toggle("Remind me before a charge", isOn: $remind)
                    if remind {
                        Stepper("Days before: \(leadDays)", value: $leadDays, in: 1...7)
                    }
                    Text("Get a local notification before a confirmed subscription's next charge.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onChange(of: remind) { _, on in
                Task {
                    if on { await LocalNotificationScheduler.requestAuthorization() }
                    else { await LocalNotificationScheduler.cancelAll() }
                }
            }
        }
    }
}
```

> NOTE: `SettingsView` and `LocalNotificationScheduler` are both in module `GoldengoFeatures`, so no extra import is needed — `import SwiftUI` and `import GoldengoData` suffice.

- [ ] **Step 2: Wire reminder sync into `SubscriptionsModel`** — in `Sources/GoldengoFeatures/Subscriptions/SubscriptionsModel.swift`, add `import GoldengoData` if not present (it is), and update `load()` plus add a private `syncReminders()`:

Replace the existing `load()` body's tail so it calls `syncReminders()`:

```swift
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        _ = try? await store.refreshSubscriptions()
        rows = (try? await store.subscriptionCandidates()) ?? []
        await syncReminders()
    }

    /// Keep scheduled reminders in sync with the confirmed set. The pure decision lives in
    /// `SubscriptionReminders.plannedRequests` (tested); this only reads settings and calls the
    /// scheduler. When the toggle is off, `plannedRequests` returns [] and `sync([])` clears any
    /// stale reminders (self-healing).
    private func syncReminders() async {
        let defaults = UserDefaults(suiteName: SharedSummary.appGroupID) ?? .standard
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let requests = SubscriptionReminders.plannedRequests(
            enabled: defaults.bool(forKey: SharedSummary.remindBeforeChargesKey),
            leadDays: defaults.integer(forKey: SharedSummary.reminderLeadDaysKey),   // 0 when unset → clamped to 1
            candidates: rows, now: .now, calendar: cal)
        await LocalNotificationScheduler.sync(requests)
    }
```

(`SubscriptionReminders`, `LocalNotificationScheduler`, `SubscriptionReminderPlanner`, and `SharedSummary` are all visible from `GoldengoFeatures`.)

- [ ] **Step 3: Build + run the Features suite** — Run: `swift build` then `swift test --filter GoldengoFeaturesTests` → clean build, tests pass.

- [ ] **Step 4: Run the FULL suite** — Run: `swift test` → all green.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/Settings/SettingsView.swift Sources/GoldengoFeatures/Subscriptions/SubscriptionsModel.swift
git commit -m "feat: Settings reminder toggle + days-before; sync confirmed-subscription reminders on load"
```

---

## Final verification (after all tasks)

- [ ] `swift test` — all green (existing + new planner/mapping tests).
- [ ] `swift build` clean.
- [ ] App build + Simulator: open Settings → the "Subscriptions" section shows the toggle; enabling it reveals the "Days before" stepper. (Notification delivery itself isn't observable in the Simulator; the planner/mapping are covered by unit tests.)
- [ ] No `Co-Authored-By` trailer in any commit.

---

## Spec Coverage Self-Review

- **Local notification before next charge** → Task 1 planner + Task 2 scheduler. ✅
- **Confirmed subscriptions only** → `SubscriptionReminders.inputs(from:)` filters `isConfirmed`; tested. ✅
- **Opt-in + configurable lead** → Settings toggle + 1…7-day stepper (Task 3). ✅
- **Stays in sync** → `SubscriptionsModel.load()` re-syncs every appear/refresh/confirm/dismiss. ✅
- **Permission UX** → request on enable, cancel on disable (Task 3). ✅
- **No Info.plist key required** for local notifications (runtime authorization). ✅

**Known limitations (documented):** reminders re-sync only when the Subscriptions tab loads (not via a background task) — acceptable since confirming/refreshing happens there; a BGTask refresh is a future enhancement. Lead-time uses `Calendar.current`; the exact fire hour follows the stored `nextChargeDate`'s time component.
