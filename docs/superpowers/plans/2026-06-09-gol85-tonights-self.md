# GOL-85 — Tonight's Self Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A same-day self-continuity ritual — a morning intention you write for yourself, surfaced back to you at night alongside a calm "close the day" reflection (usuals to confirm + spend recap + warm close).

**Architecture:** A pure, unit-tested decision core (`RitualPolicy`) decides which prompt (if any) is due given the clock + persisted intention/reflection dates. State lives in `SharedSummary` (App-Group `UserDefaults`, no SwiftData migration). Two SwiftUI `.sheet` screens (`MorningView`, `EveningView`+`EveningModel`) self-present from `RootView` on app open via `scenePhase` (mirroring GOL-84 Re-entry, which takes precedence). A Settings toggle opts in and schedules two daily local notifications via `LocalNotificationScheduler`. No `UNUserNotificationCenterDelegate` → no app-target file → no `project.rb` regen.

**Tech Stack:** Swift 6, SwiftUI, SwiftData (`@ModelActor IngestionStore`), App Groups, UserNotifications, the existing `GoldengoDesignSystem`. Tests via `swift test` (XCTest). Builds for macOS too → iOS-only APIs guarded with `#if canImport(...)`.

---

## File structure

| File | Responsibility | New/Modified |
|------|----------------|--------------|
| `Sources/GoldengoCore/RitualPolicy.swift` | Pure `RitualPrompt` enum + `RitualPolicy.prompt(...)` decision | **New** |
| `Tests/GoldengoCoreTests/RitualPolicyTests.swift` | Unit tests for the decision core | **New** |
| `Sources/GoldengoData/SharedSummary.swift` | Add ritual keys: enabled / intention(+date) / reflected | Modify (append) |
| `Tests/GoldengoDataTests/SharedSummaryRitualTests.swift` | Round-trip tests for the new keys | **New** |
| `Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift` | Add `scheduleRitual()` / `cancelRitual()` to `LocalNotificationScheduler` | Modify (append) |
| `Sources/GoldengoFeatures/Ritual/MorningView.swift` | Morning intention capture screen | **New** |
| `Sources/GoldengoFeatures/Ritual/EveningModel.swift` | `@Observable` model: load intention + ghosts + today total; confirm; mark reflected | **New** |
| `Tests/GoldengoFeaturesTests/EveningModelTests.swift` | Unit tests for `EveningModel` against an in-memory store | **New** |
| `Sources/GoldengoFeatures/Ritual/EveningView.swift` | Evening reflection screen | **New** |
| `Sources/GoldengoFeatures/RootView.swift` | `RitualSheet` wrapper, `checkRitual()`, `.sheet(item:)`, scenePhase calls | Modify |
| `Sources/GoldengoFeatures/Settings/SettingsView.swift` | "Daily check-in" toggle | Modify |

---

## Task 1: `RitualPolicy` — the pure decision core

**Files:**
- Create: `Sources/GoldengoCore/RitualPolicy.swift`
- Test: `Tests/GoldengoCoreTests/RitualPolicyTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoCoreTests/RitualPolicyTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class RitualPolicyTests: XCTestCase {
    // A fixed UTC calendar so component(.hour) is deterministic regardless of the test host's zone.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    // Build a Date at a given UTC hour on a fixed day (2026-06-09).
    private func at(_ hour: Int, day: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: 30))!
    }

    func test_morningWindow_noIntentionToday_returnsMorning() {
        let r = RitualPolicy.prompt(now: at(8), intentionDate: nil, reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .morning)
    }
    func test_morningWindow_intentionAlreadySetToday_notMorning() {
        let now = at(8)
        let r = RitualPolicy.prompt(now: now, intentionDate: at(6), reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .none)
    }
    func test_intentionSetYesterday_morningAgainToday() {
        let r = RitualPolicy.prompt(now: at(8), intentionDate: at(8, day: 8), reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .morning)
    }
    func test_eveningWindow_notReflected_returnsEvening() {
        let r = RitualPolicy.prompt(now: at(21), intentionDate: at(8), reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .evening)
    }
    func test_eveningWindow_reflectedToday_returnsNone() {
        let now = at(21)
        let r = RitualPolicy.prompt(now: now, intentionDate: at(8), reflectedDate: at(20), calendar: cal)
        XCTAssertEqual(r, .none)
    }
    func test_eveningWrapAround_oneAM_isEvening() {
        // 01:00 — past midnight is still "evening" (18:00..04:00). reflectedDate is the prior evening,
        // so on this new calendar day it is NOT reflected-today → .evening.
        let r = RitualPolicy.prompt(now: at(1), intentionDate: nil, reflectedDate: at(22, day: 8), calendar: cal)
        XCTAssertEqual(r, .evening)
    }
    func test_midday_outOfBothWindows_returnsNone() {
        let r = RitualPolicy.prompt(now: at(14), intentionDate: nil, reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .none)
    }
    func test_boundary_hour12_isNotMorning() {     // morningHours == 5..<12, so 12 is excluded
        let r = RitualPolicy.prompt(now: at(12), intentionDate: nil, reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .none)
    }
    func test_boundary_hour18_isEvening() {        // eveningStartHour == 18 (inclusive)
        let r = RitualPolicy.prompt(now: at(18), intentionDate: nil, reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .evening)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RitualPolicyTests`
Expected: FAIL — `cannot find 'RitualPolicy' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/GoldengoCore/RitualPolicy.swift`:

```swift
import Foundation

/// Which same-day ritual prompt is due right now.
public enum RitualPrompt: Sendable, Equatable { case morning, evening, none }

/// Pure decision: given the clock and the last intention/reflection dates, decide which prompt
/// (if any) should present. No persistence, no UI. Uses the LOCAL calendar by default — the
/// user's day boundaries are what "today" means here.
public enum RitualPolicy {
    public static let morningHours = 5..<12   // [05:00, 12:00)
    public static let eveningStartHour = 18   // evening window is 18:00 .. 04:00 next day
    public static let eveningEndHour = 4

    public static func prompt(now: Date, intentionDate: Date?, reflectedDate: Date?,
                              calendar: Calendar = .current) -> RitualPrompt {
        let hour = calendar.component(.hour, from: now)

        // Morning: in the morning window AND no intention captured yet today.
        if morningHours.contains(hour) {
            let setToday = intentionDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            if !setToday { return .morning }
        }
        // Evening: in the evening window (wraps past midnight) AND not reflected yet today.
        if hour >= eveningStartHour || hour < eveningEndHour {
            let reflectedToday = reflectedDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            if !reflectedToday { return .evening }
        }
        return .none
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter RitualPolicyTests`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/RitualPolicy.swift Tests/GoldengoCoreTests/RitualPolicyTests.swift
git commit -m "feat(gol-85): add RitualPolicy pure decision core"
```

---

## Task 2: `SharedSummary` — ritual storage keys

**Files:**
- Modify: `Sources/GoldengoData/SharedSummary.swift`
- Test: `Tests/GoldengoDataTests/SharedSummaryRitualTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoDataTests/SharedSummaryRitualTests.swift`:

```swift
import XCTest
@testable import GoldengoData

final class SharedSummaryRitualTests: XCTestCase {
    private func freshSummary() -> SharedSummary { SharedSummary(suiteName: "ritual-test-\(UUID().uuidString)") }

    func test_ritualEnabled_defaultsFalse_andRoundTrips() {
        let s = freshSummary()
        XCTAssertFalse(s.ritualEnabled())
        s.setRitualEnabled(true)
        XCTAssertTrue(s.ritualEnabled())
    }
    func test_intention_roundTripsTextAndDate() {
        let s = freshSummary()
        XCTAssertNil(s.readIntention())
        let d = Date(timeIntervalSince1970: 1_780_000_000)
        s.setIntention("be present", on: d)
        let read = s.readIntention()
        XCTAssertEqual(read?.text, "be present")
        XCTAssertEqual(read?.date, d)
        XCTAssertEqual(s.readIntentionDate(), d)
    }
    func test_reflected_roundTrips_nilWhenUnset() {
        let s = freshSummary()
        XCTAssertNil(s.readReflectedDate())
        let d = Date(timeIntervalSince1970: 1_780_050_000)
        s.setReflected(on: d)
        XCTAssertEqual(s.readReflectedDate(), d)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SharedSummaryRitualTests`
Expected: FAIL — `value of type 'SharedSummary' has no member 'ritualEnabled'`.

- [ ] **Step 3: Write the minimal implementation**

In `Sources/GoldengoData/SharedSummary.swift`, add these members inside the `SharedSummary` struct (place them after the `lastSeen` block at line 42, before `setPendingTab`):

```swift
    // MARK: Daily check-in ritual (GOL-85) — opt-in morning intention + evening reflection.
    public static let ritualEnabledKey = "ritualEnabled"
    public static let intentionKey = "ritualIntention"
    public static let intentionDateKey = "ritualIntentionDate"
    public static let reflectedDateKey = "ritualReflectedDate"

    public func setRitualEnabled(_ on: Bool) { defaults.set(on, forKey: Self.ritualEnabledKey) }
    public func ritualEnabled() -> Bool { defaults.bool(forKey: Self.ritualEnabledKey) }

    /// Store today's morning intention text + the moment it was captured.
    public func setIntention(_ text: String, on date: Date = .now) {
        defaults.set(text, forKey: Self.intentionKey)
        defaults.set(date, forKey: Self.intentionDateKey)
    }
    /// The stored intention, or nil if either the text or its date is missing.
    public func readIntention() -> (text: String, date: Date)? {
        guard let text = defaults.string(forKey: Self.intentionKey),
              let date = defaults.object(forKey: Self.intentionDateKey) as? Date else { return nil }
        return (text, date)
    }
    public func readIntentionDate() -> Date? { defaults.object(forKey: Self.intentionDateKey) as? Date }

    /// Mark that the evening reflection was completed at `date`.
    public func setReflected(on date: Date = .now) { defaults.set(date, forKey: Self.reflectedDateKey) }
    public func readReflectedDate() -> Date? { defaults.object(forKey: Self.reflectedDateKey) as? Date }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter SharedSummaryRitualTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/SharedSummary.swift Tests/GoldengoDataTests/SharedSummaryRitualTests.swift
git commit -m "feat(gol-85): add ritual storage keys to SharedSummary"
```

---

## Task 3: `LocalNotificationScheduler` — ritual scheduling

No unit test (pure `UNUserNotificationCenter` glue, device-verified — mirrors the existing `sync`/`cancelAll`). Prefix-filtered so it never disturbs `sub-reminder:` requests.

**Files:**
- Modify: `Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift`

- [ ] **Step 1: Add the two methods**

In `Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift`, inside `enum LocalNotificationScheduler`, add a ritual prefix and the two methods (place after `cancelAll()`, before the closing brace):

```swift
    private static let ritualPrefix = "ritual:"

    /// Schedule the two daily check-in nudges (08:00 morning, 21:00 evening), repeating.
    /// Idempotent: clears our prior ritual requests first. Best-effort no-op when notifications
    /// aren't authorized/available. Leaves `sub-reminder:` requests untouched (distinct prefix).
    public static func scheduleRitual() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(ritualPrefix) })

        func add(_ id: String, hour: Int, title: String, body: String) async {
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            var comps = DateComponents(); comps.hour = hour; comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: ritualPrefix + id,
                                                        content: content, trigger: trigger))
        }
        await add("morning", hour: 8, title: "Set today's intention", body: "What's today about?")
        await add("evening", hour: 21, title: "Close your day", body: "A calm look back at today.")
        #endif
    }

    /// Cancel both daily ritual nudges (leaves subscription reminders intact).
    public static func cancelRitual() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(ritualPrefix) })
        #endif
    }
```

- [ ] **Step 2: Verify it builds (both platforms)**

Run: `swift build`
Expected: Build complete (no errors).

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift
git commit -m "feat(gol-85): schedule/cancel daily ritual notifications"
```

---

## Task 4: `MorningView` — intention capture screen

No unit test (a SwiftUI screen, device-verified). Keyboard dismissal per project conventions: Return submits, tap-outside clears focus, focus clears after save — **never** a keyboard Done toolbar.

**Files:**
- Create: `Sources/GoldengoFeatures/Ritual/MorningView.swift`

- [ ] **Step 1: Create the view**

Create `Sources/GoldengoFeatures/Ritual/MorningView.swift`:

```swift
import SwiftUI
import GoldengoData
import GoldengoDesignSystem

/// Morning intention capture — "a letter from this-morning-you". One line + Save / Skip.
public struct MorningView: View {
    let onDone: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    public init(onDone: @escaping () -> Void) { self.onDone = onDone }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        focused = false
        if !trimmed.isEmpty {
            SharedSummary().setIntention(trimmed, on: .now)
            GoldengoHaptics.spendLanded()
        }
        onDone()
    }

    public var body: some View {
        VStack(spacing: GoldengoTheme.Spacing.l) {
            Spacer()
            Image(systemName: "sun.max.fill")
                .font(.system(size: 48)).foregroundStyle(GoldengoTheme.accent)
            Text("What's today about?")
                .font(.title2.weight(.bold))
            Text("One line for tonight-you to read back.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, GoldengoTheme.Spacing.xl)
            TextField("Today, I want to…", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, GoldengoTheme.Spacing.l)
            Spacer()
            Button(action: save) {
                Text("Save").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
            }
            .background(GoldengoTheme.accent).foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
            .padding(.horizontal, GoldengoTheme.Spacing.l)
            Button("Skip for today", action: onDone)
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.bottom, GoldengoTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.goldengoBackground.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { focused = false }     // tap-outside dismissal (no keyboard toolbar)
        .onAppear { focused = true }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoFeatures/Ritual/MorningView.swift
git commit -m "feat(gol-85): add MorningView intention capture"
```

---

## Task 5: `EveningModel` — load + confirm + reflect

**Files:**
- Create: `Sources/GoldengoFeatures/Ritual/EveningModel.swift`
- Test: `Tests/GoldengoFeaturesTests/EveningModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoFeaturesTests/EveningModelTests.swift`:

```swift
import XCTest
import SwiftData
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class EveningModelTests: XCTestCase {
    /// Log a daily coffee for the last `startDaysAgo` days, ending yesterday (none today).
    private func seedDailyCoffee(_ store: IngestionStore, startDaysAgo: Int = 7) async throws {
        for k in stride(from: startDaysAgo, through: 1, by: -1) {
            try await store.logManual(amount: 200, currency: .all, merchant: "Coffee",
                                      categoryName: nil, date: Date().addingTimeInterval(Double(-k) * 86_400))
        }
    }
    private func freshSummary() -> SharedSummary { SharedSummary(suiteName: "evening-\(UUID().uuidString)") }

    func test_load_surfacesTodaysIntention_ghosts_andTotal() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store)
        try await store.logManual(amount: 500, currency: .all, merchant: "Lunch", categoryName: nil, date: .now)
        let summary = freshSummary()
        summary.setIntention("be present", on: .now)

        let model = EveningModel(store: store, currency: .all, summary: summary)
        await model.load()

        XCTAssertEqual(model.intention, "be present")
        XCTAssertTrue(model.ghosts.contains { $0.displayName == "Coffee" })
        XCTAssertFalse(model.todayTotalText.isEmpty)
    }

    func test_load_intentionNil_whenSetOnAPriorDay() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = freshSummary()
        summary.setIntention("old note", on: Date().addingTimeInterval(-2 * 86_400))
        let model = EveningModel(store: store, summary: summary)
        await model.load()
        XCTAssertNil(model.intention)
    }

    func test_confirm_logsTheUsual() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store)
        let model = EveningModel(store: store, summary: freshSummary())
        await model.load()
        let ghost = try XCTUnwrap(model.ghosts.first)
        let before = try await store.expenseCount()
        await model.confirm(ghost)
        let after = try await store.expenseCount()
        XCTAssertEqual(after, before + 1)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter EveningModelTests`
Expected: FAIL — `cannot find 'EveningModel' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/GoldengoFeatures/Ritual/EveningModel.swift`:

```swift
import Foundation
import Observation
import GoldengoCore
import GoldengoData

/// Backs the evening reflection: today's morning intention (if any), today's usuals to confirm,
/// and a calm spend recap. `summary` is injectable so the intention read is testable in isolation.
@MainActor
@Observable
public final class EveningModel {
    private let store: IngestionStore
    private let summary: SharedSummary
    public var currency: CurrencyCode
    public private(set) var intention: String?
    public private(set) var ghosts: [RhythmGhost] = []
    public private(set) var todayTotalText: String = ""

    public init(store: IngestionStore, currency: CurrencyCode = .all, summary: SharedSummary = SharedSummary()) {
        self.store = store; self.currency = currency; self.summary = summary
    }

    public func load() async {
        // Only show the intention if it was set TODAY (a stale prior-day note is not "this morning").
        if let saved = summary.readIntention(), Calendar.current.isDate(saved.date, inSameDayAs: .now) {
            intention = saved.text
        } else {
            intention = nil
        }
        let rates = ExchangeRateCache().load() ?? SeedRates.table
        ghosts = (try? await store.rhythmGhosts(now: .now)) ?? []
        let total = (try? await store.todayTotal(in: currency, rates: rates)) ?? 0
        todayTotalText = Money(amount: total, currency: currency).formatted()
    }

    /// Confirm a usual (logs it at its median), then reload so it clears from the list.
    public func confirm(_ ghost: RhythmGhost) async {
        try? await store.confirmRhythmGhost(ghost, amount: ghost.amount)
        await load()
    }

    /// Record that tonight's reflection is done (drives the once-per-day suppression).
    public func markReflected() { summary.setReflected(on: .now) }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter EveningModelTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/Ritual/EveningModel.swift Tests/GoldengoFeaturesTests/EveningModelTests.swift
git commit -m "feat(gol-85): add EveningModel (intention + usuals + recap)"
```

---

## Task 6: `EveningView` — reflection screen

No unit test (a SwiftUI screen; its logic lives in the tested `EveningModel`).

**Files:**
- Create: `Sources/GoldengoFeatures/Ritual/EveningView.swift`

- [ ] **Step 1: Create the view**

Create `Sources/GoldengoFeatures/Ritual/EveningView.swift`:

```swift
import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// The evening "close the day" reflection: surfaces this morning's intention, today's usuals to
/// confirm, a calm spend recap, and a warm close. Accountability to yourself — never scolding.
public struct EveningView: View {
    @State private var model: EveningModel
    let onDone: () -> Void
    public init(model: EveningModel, onDone: @escaping () -> Void) {
        _model = State(initialValue: model); self.onDone = onDone
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                Text("Close your day").font(.title.weight(.bold))

                // This morning's intention (or a gentle "no note" line).
                if let intention = model.intention {
                    VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.s) {
                        Text("This morning you said").font(.caption).foregroundStyle(.secondary)
                        Text("“\(intention)”").font(.title3.weight(.semibold))
                    }
                } else {
                    Text("No note this morning — that's fine.")
                        .font(.body).foregroundStyle(.secondary)
                }

                // Today's usuals — one tap each to confirm.
                if !model.ghosts.isEmpty {
                    Text("Anything usual today?").font(.headline)
                    ForEach(model.ghosts) { ghost in
                        Button {
                            GoldengoHaptics.spendLanded()
                            Task { await model.confirm(ghost) }
                        } label: {
                            HStack {
                                Text(ghost.displayName)
                                Spacer()
                                Text(Money(amount: ghost.amount,
                                           currency: CurrencyCode(ghost.currencyCode)).formatted())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "plus.circle.fill").foregroundStyle(GoldengoTheme.accent)
                            }
                            .padding()
                            .background(Color.goldengoSurface)
                            .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Calm spend recap (no judgement framing).
                HStack {
                    Text("Today").foregroundStyle(.secondary)
                    Spacer()
                    Text(model.todayTotalText).font(.headline)
                }
                .padding(.vertical, GoldengoTheme.Spacing.s)

                Text("You were trying. Rest well.")
                    .font(.body).foregroundStyle(.secondary)

                Button {
                    model.markReflected()
                    onDone()
                } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                }
                .background(GoldengoTheme.accent).foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
            }
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
        .task { await model.load() }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoFeatures/Ritual/EveningView.swift
git commit -m "feat(gol-85): add EveningView reflection screen"
```

---

## Task 7: `RootView` wiring — present the right sheet once per day

The decision logic is already tested in `RitualPolicy`; this task is the presentation glue (device-verified). Re-entry takes precedence; the ritual is opt-in gated.

**Files:**
- Modify: `Sources/GoldengoFeatures/RootView.swift`

- [ ] **Step 1: Add the `RitualSheet` wrapper type**

In `Sources/GoldengoFeatures/RootView.swift`, just after the `ReEntryPrompt` struct (line 15), add:

```swift
/// Drives the ritual `.sheet(item:)` (RitualPrompt isn't Identifiable, and we need a fresh identity
/// per presentation). Only `.morning`/`.evening` are ever wrapped (never `.none`).
public struct RitualSheet: Identifiable { public let id = UUID(); public let kind: RitualPrompt }
```

- [ ] **Step 2: Add the state property**

After `@State private var reEntryPrompt: ReEntryPrompt?` (line 23), add:

```swift
    @State private var ritualSheet: RitualSheet?          // daily check-in (GOL-85), opt-in
```

- [ ] **Step 3: Add the `checkRitual()` helper**

Immediately after the `checkReEntry()` method (after its closing brace at line 71), add:

```swift
    /// Present the daily check-in sheet if one is due. Re-entry takes precedence (if its soft-landing
    /// is showing this activation, skip the ritual). Opt-in gated. Called right after `checkReEntry()`
    /// in both the cold-launch `.task` and `.onChange(scenePhase) == .active`. The `ritualSheet == nil`
    /// guard + the once-per-day intention/reflected dates make re-presenting within a day impossible.
    private func checkRitual() {
        guard reEntryPrompt == nil, ritualSheet == nil else { return }
        let summary = SharedSummary()
        guard summary.ritualEnabled() else { return }
        let prompt = RitualPolicy.prompt(now: .now,
                                         intentionDate: summary.readIntentionDate(),
                                         reflectedDate: summary.readReflectedDate())
        if prompt != .none { ritualSheet = RitualSheet(kind: prompt) }
    }
```

- [ ] **Step 4: Add the `.sheet(item:)` presenter**

After the `#if os(iOS) ... .fullScreenCover(item: $reEntryPrompt) ... #endif` block (lines 125–129), add:

```swift
        .sheet(item: $ritualSheet) { s in
            if s.kind == .morning {
                MorningView(onDone: { ritualSheet = nil })
            } else {
                EveningView(model: EveningModel(store: store,
                                                currency: SharedSummary().readPreferredCurrency()),
                            onDone: { ritualSheet = nil })
            }
        }
```

- [ ] **Step 5: Call `checkRitual()` from the cold-launch `.task`**

In the `.task { ... }` block (lines 131–134), add the ritual check right after `checkReEntry()`:

```swift
        .task {
            checkReEntry()            // cold-launch re-entry check (onChange(scenePhase) misses the initial .active)
            checkRitual()             // then the daily check-in (Re-entry takes precedence)
            await recentModel.load()  // Home is the landing tab
        }
```

- [ ] **Step 6: Call `checkRitual()` from `.onChange(scenePhase) == .active`**

In the `.active` case of the `.onChange(of: scenePhase)` switch (lines 143–148), add `checkRitual()` right after `checkReEntry()`:

```swift
            case .active:
                checkReEntry()
                checkRitual()
                applyPendingTab()
                // An expense may have been logged via the Quick-Log shortcut while we were
                // backgrounded; reload so it appears on Home without a manual pull-to-refresh.
                Task { await recentModel.load() }
```

- [ ] **Step 7: Verify it builds (both platforms — `.sheet` is cross-platform, no `#if` needed)**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 8: Commit**

```bash
git add Sources/GoldengoFeatures/RootView.swift
git commit -m "feat(gol-85): wire daily check-in sheets into RootView"
```

---

## Task 8: `SettingsView` — "Daily check-in" toggle

No unit test (SwiftUI + `@AppStorage`; the schedule/cancel side effect is device-verified).

**Files:**
- Modify: `Sources/GoldengoFeatures/Settings/SettingsView.swift`

- [ ] **Step 1: Add the backing `@AppStorage`**

In `Sources/GoldengoFeatures/Settings/SettingsView.swift`, after the `leadDays` `@AppStorage` (line 11), add:

```swift
    @AppStorage(SharedSummary.ritualEnabledKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var ritualEnabled: Bool = false
```

- [ ] **Step 2: Add the toggle Section**

After the `Section("Subscriptions") { ... }` block (closes at line 78), add a new section:

```swift
                Section("Daily check-in") {
                    Toggle("Morning + evening check-in", isOn: $ritualEnabled)
                    Text("A morning intention you set for yourself, surfaced back to you at night with a calm recap. Two gentle nudges a day.")
                        .font(.caption).foregroundStyle(.secondary)
                }
```

- [ ] **Step 3: Add the schedule/cancel side effect**

After the existing `.onChange(of: remind) { ... }` modifier (closes at line 98), add a sibling `.onChange`:

```swift
            // Enabling requests notification permission then schedules the two daily nudges; if
            // permission is denied we leave the toggle ON (the screens still self-present on app
            // open — notifications are just a bonus). Disabling cancels only the ritual requests.
            .onChange(of: ritualEnabled) { _, on in
                Task { @MainActor in
                    if on {
                        await LocalNotificationScheduler.requestAuthorization()
                        await LocalNotificationScheduler.scheduleRitual()
                    } else {
                        await LocalNotificationScheduler.cancelRitual()
                    }
                }
            }
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/Settings/SettingsView.swift
git commit -m "feat(gol-85): add Daily check-in toggle to Settings"
```

---

## Task 9: Full verification — suite, sim build, device install, ticket

**Files:** none (verification + release).

- [ ] **Step 1: Run the FULL test suite (not just filtered)**

Run: `swift test`
Expected: ALL tests pass (the prior 259 + the new RitualPolicy/SharedSummary/EveningModel tests). If anything fails, fix before proceeding — do not skip.

- [ ] **Step 2: Simulator build (catches iOS-only / SwiftUI issues `swift build` misses)**

Run:
```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath AppProject/.build build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Second-Opus code review of the full diff**

Dispatch a review agent (model: opus) over `git diff main...HEAD` for the branch with the receiving-code-review workflow. Address any Critical/Major findings before merge; note minor ones.

- [ ] **Step 4: Device build**

Run:
```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -derivedDataPath AppProject/.build-device build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Install on device**

Run:
```bash
xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E \
  AppProject/.build-device/Build/Products/Debug-iphoneos/Goldengo.app
```
Expected: install succeeds.

- [ ] **Step 6: Merge to main + push**

Use the finishing-a-development-branch workflow: ff-merge `gol-85-tonights-self` into `main`, push.

- [ ] **Step 7: Set GOL-85 → To Verify**

Move the ticket to **To Verify** with a comment summarizing what shipped and the on-device verification steps (enable the toggle in Settings; confirm morning sheet appears in the 5–12h window with no intention set; confirm evening sheet in the 18–4h window surfaces the morning note + usuals + recap; confirm the two notifications fire at 08:00 / 21:00).

---

## Self-review notes (author)

**Spec coverage:** RitualPolicy (Task 1) ✓ · SharedSummary keys (Task 2) ✓ · scheduleRitual/cancelRitual (Task 3) ✓ · MorningView (Task 4) ✓ · EveningModel (Task 5) ✓ · EveningView (Task 6) ✓ · RootView checkRitual + precedence + .sheet(item:) (Task 7) ✓ · Settings toggle default-off (Task 8) ✓ · tests RitualPolicy/SharedSummary/EveningModel + device verify (Task 9) ✓.

**Type consistency:** `RitualPrompt`/`RitualPolicy.prompt(now:intentionDate:reflectedDate:calendar:)` (Task 1) used verbatim in Task 7. `SharedSummary.ritualEnabledKey`/`setIntention(_:on:)`/`readIntention()`/`readIntentionDate()`/`setReflected(on:)`/`readReflectedDate()`/`ritualEnabled()` defined in Task 2, used in Tasks 5/7/8. `EveningModel(store:currency:summary:)` + `.load()`/`.confirm(_:)`/`.markReflected()`/`.intention`/`.ghosts`/`.todayTotalText` defined in Task 5, used in Tasks 6/7. `RitualSheet { id; kind }` defined Task 7 Step 1, used Step 4. `LocalNotificationScheduler.scheduleRitual()`/`cancelRitual()` defined Task 3, used Task 8.

**Edge cases (from spec):** evening wrap-around (Task 1 test) ✓ · no-intention-today gentle line (Task 6 `if let … else`) ✓ · Re-entry precedence (Task 7 guard) ✓ · once-per-day suppression (intention/reflected same-day checks) ✓ · macOS no-op (all UN code under `#if canImport(UserNotifications)`; `.sheet` cross-platform) ✓ · denied permission leaves toggle on, screens still self-present (Task 8 comment + no toggle-flip-back) ✓.
