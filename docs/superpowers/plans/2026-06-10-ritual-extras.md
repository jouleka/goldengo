# Tonight's Self Extras (GOL-93) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Custom check-in nudge times (clamped to the existing windows), an automatic intention journal with a "Past notes" list, and a notifications-denied hint in Settings.

**Architecture:** Pure clamp + journal logic in GoldengoCore (tested); minutes-from-midnight Ints and a JSON history array in `SharedSummary` (GoldengoData, tested); scheduler/Settings/EveningView wiring in GoldengoFeatures (device-verified). `RitualPolicy.prompt` and its windows stay byte-identical.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, UserDefaults (App Group), UNUserNotificationCenter, XCTest. Spec: `docs/superpowers/specs/2026-06-10-ritual-extras-design.md`.

**Hard rules (CLAUDE.md / gotchas):** full `swift test` before any green claim (baseline 322; this plan adds 8 → 330). Package builds on macOS — `#if canImport(UserNotifications)` / `#if os(iOS)` guard platform API. No keyboard "Done" toolbar anywhere.

**Branch:** `git checkout -b gol-93-ritual-extras` off `main` before Task 1.

---

### Task 1: Pure core — nudge clamps + `IntentionJournal`

**Files:**
- Modify: `Sources/GoldengoCore/RitualPolicy.swift` (append inside the enum)
- Create: `Sources/GoldengoCore/IntentionJournal.swift`
- Test: `Tests/GoldengoCoreTests/RitualPolicyTests.swift` (append), Create `Tests/GoldengoCoreTests/IntentionJournalTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `RitualPolicyTests.swift` (inside the class):

```swift
    func test_clampNudges_pinToTheirWindows() {
        XCTAssertEqual(RitualPolicy.clampMorningNudge(minutes: 480), 480)    // 08:00 passes through
        XCTAssertEqual(RitualPolicy.clampMorningNudge(minutes: 0), 300)     // below → 05:00
        XCTAssertEqual(RitualPolicy.clampMorningNudge(minutes: 900), 705)   // above → 11:45
        XCTAssertEqual(RitualPolicy.clampEveningNudge(minutes: 1260), 1260) // 21:00 passes through
        XCTAssertEqual(RitualPolicy.clampEveningNudge(minutes: 600), 1080)  // below → 18:00
        XCTAssertEqual(RitualPolicy.clampEveningNudge(minutes: 1440), 1425) // above → 23:45
        // The shipped defaults must already be inside the windows (no first-run clamping).
        XCTAssertEqual(RitualPolicy.clampMorningNudge(minutes: RitualPolicy.defaultMorningNudgeMinutes),
                       RitualPolicy.defaultMorningNudgeMinutes)
        XCTAssertEqual(RitualPolicy.clampEveningNudge(minutes: RitualPolicy.defaultEveningNudgeMinutes),
                       RitualPolicy.defaultEveningNudgeMinutes)
    }
```

Create `IntentionJournalTests.swift`:

```swift
import XCTest
import GoldengoCore

final class IntentionJournalTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func test_append_keepsChronologicalOrder() {
        var history: [IntentionEntry] = []
        history = IntentionJournal.append(.init(date: day(2026, 6, 8), text: "rest"), to: history, calendar: cal)
        history = IntentionJournal.append(.init(date: day(2026, 6, 9), text: "focus"), to: history, calendar: cal)
        XCTAssertEqual(history.map(\.text), ["rest", "focus"], "Newest last — display layers reverse")
    }

    func test_sameDayAppend_replaces() {
        var history = [IntentionEntry(date: day(2026, 6, 9, hour: 7), text: "draft")]
        history = IntentionJournal.append(.init(date: day(2026, 6, 9, hour: 9), text: "final"), to: history, calendar: cal)
        XCTAssertEqual(history.count, 1, "Editing the morning note must not journal twice")
        XCTAssertEqual(history.first?.text, "final")
    }

    func test_capacity_dropsOldest() {
        var history = (0..<IntentionJournal.capacity).map {
            IntentionEntry(date: day(2025, 1, 1).addingTimeInterval(Double($0) * 86_400), text: "n\($0)")
        }
        history = IntentionJournal.append(.init(date: day(2026, 6, 9), text: "newest"), to: history, calendar: cal)
        XCTAssertEqual(history.count, IntentionJournal.capacity)
        XCTAssertEqual(history.first?.text, "n1", "Oldest entry dropped")
        XCTAssertEqual(history.last?.text, "newest")
    }

    func test_entryCodableRoundTrip() throws {
        let entry = IntentionEntry(date: day(2026, 6, 9), text: "be kind")
        let decoded = try JSONDecoder().decode([IntentionEntry].self,
                                               from: JSONEncoder().encode([entry]))
        XCTAssertEqual(decoded, [entry])
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter "RitualPolicyTests|IntentionJournalTests" 2>&1 | grep -E "error:|Executed" | head -5`
Expected: COMPILE FAILURE — `cannot find 'IntentionJournal' / no member 'clampMorningNudge'`

- [ ] **Step 3: Implement**

Append inside `public enum RitualPolicy` in `RitualPolicy.swift`:

```swift
    // GOL-93: user-schedulable nudge times, stored as minutes-from-midnight. Clamped to the
    // self-presenting windows above so a nudge can never fire where no sheet would present.
    public static let defaultMorningNudgeMinutes = 8 * 60      // 08:00
    public static let defaultEveningNudgeMinutes = 21 * 60     // 21:00

    /// Pin a morning-nudge choice inside the morning window (05:00–11:45).
    public static func clampMorningNudge(minutes: Int) -> Int { min(max(minutes, 5 * 60), 11 * 60 + 45) }
    /// Pin an evening-nudge choice inside the evening window's same-day stretch (18:00–23:45).
    public static func clampEveningNudge(minutes: Int) -> Int { min(max(minutes, 18 * 60), 23 * 60 + 45) }
```

Create `Sources/GoldengoCore/IntentionJournal.swift`:

```swift
import Foundation

/// One saved morning intention (GOL-93). Codable for the SharedSummary JSON blob.
public struct IntentionEntry: Codable, Equatable, Sendable {
    public var date: Date
    public var text: String
    public init(date: Date, text: String) { self.date = date; self.text = text }
}

/// Pure journal rules for past intentions: same-day saves replace (editing the morning note
/// never duplicates) and the journal is capped — persistence is the caller's concern.
public enum IntentionJournal {
    public static let capacity = 365

    /// Append `entry`, replacing an existing same-calendar-day entry, dropping the oldest
    /// beyond `capacity`. Input and output are oldest-first (newest LAST).
    public static func append(_ entry: IntentionEntry, to history: [IntentionEntry],
                              calendar: Calendar) -> [IntentionEntry] {
        var kept = history.filter { !calendar.isDate($0.date, inSameDayAs: entry.date) }
        kept.append(entry)
        if kept.count > capacity { kept.removeFirst(kept.count - capacity) }
        return kept
    }
}
```

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter "RitualPolicyTests|IntentionJournalTests" 2>&1 | grep -E "error:|Executed" | head -5`
Expected: RitualPolicyTests + 4 IntentionJournalTests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/RitualPolicy.swift Sources/GoldengoCore/IntentionJournal.swift Tests/GoldengoCoreTests/RitualPolicyTests.swift Tests/GoldengoCoreTests/IntentionJournalTests.swift
git commit -m "feat(gol-93): nudge-time clamps + pure intention journal"
```

---

### Task 2: `SharedSummary` — minutes keys + history storage

**Files:**
- Modify: `Sources/GoldengoData/SharedSummary.swift` (the "Daily check-in ritual" MARK section, ~line 44)
- Test: `Tests/GoldengoDataTests/SharedSummaryRitualTests.swift` (append)

- [ ] **Step 1: Write the failing tests**

Append inside the class in `SharedSummaryRitualTests.swift` (match its existing setup — it constructs a `SharedSummary` against a test suite; reuse the same property names the file already uses):

```swift
    func test_nudgeMinutes_roundTrip_andWindowDefaults() {
        XCTAssertEqual(summary.ritualMorningMinutes(), RitualPolicy.defaultMorningNudgeMinutes,
                       "Unset reads as the shipped 08:00 default")
        XCTAssertEqual(summary.ritualEveningMinutes(), RitualPolicy.defaultEveningNudgeMinutes)
        summary.setRitualMorningMinutes(6 * 60 + 30)
        summary.setRitualEveningMinutes(22 * 60)
        XCTAssertEqual(summary.ritualMorningMinutes(), 390)
        XCTAssertEqual(summary.ritualEveningMinutes(), 1320)
    }

    func test_intentionHistory_roundTrip_andCorruptDataYieldsEmpty() {
        XCTAssertEqual(summary.readIntentionHistory(), [])
        let entries = [IntentionEntry(date: Date(timeIntervalSinceReferenceDate: 0), text: "begin")]
        summary.setIntentionHistory(entries)
        XCTAssertEqual(summary.readIntentionHistory(), entries)
        summary.defaultsForTesting.set(Data("not json".utf8), forKey: SharedSummary.ritualIntentionHistoryKey)
        XCTAssertEqual(summary.readIntentionHistory(), [], "Corrupt blob restarts the journal, never crashes")
    }

    func test_setIntention_journalsAutomatically_sameDayReplaces() {
        summary.setIntention("draft", on: Date(timeIntervalSinceReferenceDate: 1_000))
        summary.setIntention("final", on: Date(timeIntervalSinceReferenceDate: 2_000))   // same day
        XCTAssertEqual(summary.readIntentionHistory().map(\.text), ["final"],
                       "Saving twice in one morning keeps one journal entry")
    }
```

NOTE: if the test file exposes no `defaultsForTesting`, check how its existing tests reach the suite's `UserDefaults` and write through the same path; add an internal accessor only if none exists.

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter SharedSummaryRitualTests 2>&1 | grep -E "error:|Executed" | head -5`
Expected: COMPILE FAILURE — `no member 'ritualMorningMinutes'`

- [ ] **Step 3: Implement**

In `SharedSummary.swift`, extend the ritual MARK section:

```swift
    public static let ritualMorningMinutesKey = "ritualMorningMinutes"
    public static let ritualEveningMinutesKey = "ritualEveningMinutes"
    public static let ritualIntentionHistoryKey = "ritualIntentionHistory"

    /// Nudge times as minutes-from-midnight (GOL-93) — Ints avoid Date/timezone traps.
    /// Unset reads as the shipped defaults (object(forKey:) nil-check, NOT integer(forKey:),
    /// which would silently turn "unset" into midnight).
    public func setRitualMorningMinutes(_ m: Int) { defaults.set(m, forKey: Self.ritualMorningMinutesKey) }
    public func ritualMorningMinutes() -> Int {
        defaults.object(forKey: Self.ritualMorningMinutesKey) as? Int ?? RitualPolicy.defaultMorningNudgeMinutes
    }
    public func setRitualEveningMinutes(_ m: Int) { defaults.set(m, forKey: Self.ritualEveningMinutesKey) }
    public func ritualEveningMinutes() -> Int {
        defaults.object(forKey: Self.ritualEveningMinutesKey) as? Int ?? RitualPolicy.defaultEveningNudgeMinutes
    }

    /// The intention journal (GOL-93), JSON-encoded. Corrupt/missing → [] (restart, never crash).
    public func readIntentionHistory() -> [IntentionEntry] {
        guard let data = defaults.data(forKey: Self.ritualIntentionHistoryKey),
              let entries = try? JSONDecoder().decode([IntentionEntry].self, from: data) else { return [] }
        return entries
    }
    public func setIntentionHistory(_ entries: [IntentionEntry]) {
        defaults.set((try? JSONEncoder().encode(entries)) ?? Data(), forKey: Self.ritualIntentionHistoryKey)
    }
```

And make `setIntention` journal automatically (modify the existing method):

```swift
    /// Store today's morning intention text + the moment it was captured, and journal it
    /// (same-day re-saves replace their journal entry — IntentionJournal rules).
    public func setIntention(_ text: String, on date: Date = .now) {
        defaults.set(text, forKey: Self.intentionKey)
        defaults.set(date, forKey: Self.intentionDateKey)
        setIntentionHistory(IntentionJournal.append(IntentionEntry(date: date, text: text),
                                                    to: readIntentionHistory(), calendar: .current))
    }
```

(`SharedSummary.swift` already imports GoldengoCore — verify; add the import if not.)

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter SharedSummaryRitualTests 2>&1 | grep -E "error:|Executed" | head -5`
Expected: all SharedSummaryRitualTests green (existing + 3 new)

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/SharedSummary.swift Tests/GoldengoDataTests/SharedSummaryRitualTests.swift
git commit -m "feat(gol-93): nudge-minute storage + automatic intention journal"
```

---

### Task 3: Features wiring — scheduler, Settings, Past notes

No unit tests (notification + UI surface) — device-verified per spec; the suite + sim build gate the task.

**Files:**
- Modify: `Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift:82-103` (`scheduleRitual`), append `authorizationDenied()`
- Modify: `Sources/GoldengoFeatures/Settings/SettingsView.swift` ("Daily check-in" section + onChange)
- Modify: `Sources/GoldengoFeatures/Ritual/EveningView.swift` (Past notes link), `Sources/GoldengoFeatures/Ritual/EveningModel.swift` (expose past notes)
- Create: `Sources/GoldengoFeatures/Ritual/PastNotesView.swift`

- [ ] **Step 1: Scheduler reads the stored minutes + denied check**

Replace the hardcoded hours in `scheduleRitual()`:

```swift
    /// Schedule the two daily check-in nudges at the user's chosen times (defaults 08:00/21:00),
    /// repeating. Idempotent: clears our prior ritual requests first. Best-effort no-op when
    /// notifications aren't authorized/available. Leaves `sub-reminder:` requests untouched.
    public static func scheduleRitual() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(ritualPrefix) })

        func add(_ id: String, minutes: Int, title: String, body: String) async {
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            var comps = DateComponents(); comps.hour = minutes / 60; comps.minute = minutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: ritualPrefix + id,
                                                        content: content, trigger: trigger))
        }
        // Clamped defensively — old builds or tampered defaults can't push a nudge outside
        // the self-presenting windows.
        let summary = SharedSummary()
        await add("morning", minutes: RitualPolicy.clampMorningNudge(minutes: summary.ritualMorningMinutes()),
                  title: "Set today's intention", body: "What's today about?")
        await add("evening", minutes: RitualPolicy.clampEveningNudge(minutes: summary.ritualEveningMinutes()),
                  title: "Close your day", body: "A calm look back at today.")
        #endif
    }
```

Append next to it:

```swift
    /// True when the user has explicitly denied notification permission — drives the quiet
    /// "notifications are off" hint in Settings (GOL-93). False where the framework is absent.
    public static func authorizationDenied() async -> Bool {
        #if canImport(UserNotifications)
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        #else
        return false
        #endif
    }
```

- [ ] **Step 2: Settings — pickers + hint**

In `SettingsView.swift` add state + helpers (near the existing `@AppStorage` properties):

```swift
    // GOL-93: nudge-time pickers (minutes-from-midnight in SharedSummary; Dates only for the UI).
    @State private var morningNudge: Date = SettingsView.date(fromMinutes: SharedSummary().ritualMorningMinutes())
    @State private var eveningNudge: Date = SettingsView.date(fromMinutes: SharedSummary().ritualEveningMinutes())
    @State private var notificationsDenied = false

    /// Minutes ↔ Date on a fixed reference day — the pickers only ever read hour+minute.
    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0,
                              of: Date(timeIntervalSinceReferenceDate: 0)) ?? .now
    }
    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
```

Replace the "Daily check-in" `Section` body:

```swift
                Section("Daily check-in") {
                    Toggle("Morning + evening check-in", isOn: $ritualEnabled)
                    if ritualEnabled {
                        DatePicker("Morning nudge", selection: $morningNudge,
                                   in: Self.date(fromMinutes: 5 * 60)...Self.date(fromMinutes: 11 * 60 + 45),
                                   displayedComponents: .hourAndMinute)
                        DatePicker("Evening nudge", selection: $eveningNudge,
                                   in: Self.date(fromMinutes: 18 * 60)...Self.date(fromMinutes: 23 * 60 + 45),
                                   displayedComponents: .hourAndMinute)
                        if notificationsDenied {
                            // Quiet remediation, never a scold: the sheets still self-present.
                            Text("Notifications are off — check-ins won't nudge you.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Open iOS Settings") {
                                #if os(iOS)
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                                #endif
                            }
                            .font(.caption)
                        }
                    }
                    Text("A morning intention you set for yourself, surfaced back to you at night with a calm recap. Two gentle nudges a day.")
                        .font(.caption).foregroundStyle(.secondary)
                }
```

Add the change handlers next to the existing `.onChange(of: ritualEnabled)` (and extend that one to refresh the denied flag):

```swift
            .task { notificationsDenied = await LocalNotificationScheduler.authorizationDenied() }
            .onChange(of: morningNudge) { _, picked in
                SharedSummary().setRitualMorningMinutes(RitualPolicy.clampMorningNudge(minutes: Self.minutes(from: picked)))
                Task { await LocalNotificationScheduler.scheduleRitual() }
            }
            .onChange(of: eveningNudge) { _, picked in
                SharedSummary().setRitualEveningMinutes(RitualPolicy.clampEveningNudge(minutes: Self.minutes(from: picked)))
                Task { await LocalNotificationScheduler.scheduleRitual() }
            }
```

and inside the existing `ritualEnabled` onChange's `if on` branch, after `scheduleRitual()`:

```swift
                        notificationsDenied = await LocalNotificationScheduler.authorizationDenied()
```

Check `SettingsView.swift` imports `GoldengoCore` and (under `#if os(iOS)`) `UIKit`; add what's missing.

- [ ] **Step 3: EveningModel exposes past notes**

In `EveningModel.swift`, add a published property and load it (match the model's existing load style):

```swift
    /// Past mornings' notes (newest first), EXCLUDING today's — drives the "Past notes" link.
    public private(set) var pastNotes: [IntentionEntry] = []
```

and inside `load()`:

```swift
        pastNotes = Array(SharedSummary().readIntentionHistory()
            .filter { !Calendar.current.isDate($0.date, inSameDayAs: .now) }
            .reversed())
```

- [ ] **Step 4: Past notes link + view**

In `EveningView.swift` add state + the link below the intention block (after the `if let intention … else …` group):

```swift
                if !model.pastNotes.isEmpty {
                    Button("Past notes") { showPastNotes = true }
                        .font(.caption).foregroundStyle(.secondary)
                }
```

with `@State private var showPastNotes = false` next to the model, and on the `ScrollView` (next to `.task`):

```swift
        .sheet(isPresented: $showPastNotes) { PastNotesView(notes: model.pastNotes) }
```

Create `Sources/GoldengoFeatures/Ritual/PastNotesView.swift`:

```swift
import SwiftUI
import GoldengoCore
import GoldengoDesignSystem

/// A quiet, read-only journal of past mornings' intentions (GOL-93). Newest first.
public struct PastNotesView: View {
    let notes: [IntentionEntry]
    public init(notes: [IntentionEntry]) { self.notes = notes }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
                Text("Past notes").font(.title2.weight(.bold))
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.date.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(.caption).foregroundStyle(.secondary)
                        Text("“\(note.text)”").font(.body)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(GoldengoTheme.Spacing.l)
        }
        .background(Color.goldengoBackground.ignoresSafeArea())
    }
}
```

- [ ] **Step 5: Full suite + simulator build**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests|error:" | tail -2`
Expected: 330 tests, 0 failures — any failure or signal is blocking.

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoFeatures Tests
git commit -m "feat(gol-93): nudge-time pickers, past-notes journal, notifications-off hint"
```

---

### After the plan

Per the standard cycle (not plan steps): adversarial review of `git diff main...HEAD`, fix confirmed findings, ff-merge to `main`, push, device build + install, GOL-93 → **To Verify** with a summary comment.
