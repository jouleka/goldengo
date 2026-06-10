# GOL-85 extras — custom check-in times, intention history, notifications-off hint

**Status:** design approved; pending spec review.
**Date:** 2026-06-10.
**Origin:** the three follow-ups noted out-of-scope in the GOL-85 spec (`2026-06-09-tonights-self-design.md`).
**Builds on:** `RitualPolicy` (GoldengoCore), `SharedSummary` ritual keys (GoldengoData), `LocalNotificationScheduler.scheduleRitual/cancelRitual` (GoldengoFeatures, in `SubscriptionReminders.swift`), `SettingsView` "Daily check-in" section, `EveningView`/`EveningModel`.

## Goal

Three small, independent refinements to Tonight's Self: the two daily nudges become user-schedulable (within the existing self-presenting windows), saved intentions quietly accumulate into a browsable journal, and Settings tells you when the check-in toggle is on but iOS notifications are denied.

## Decision record (brainstorm)

- **All three extras in one cycle** — each is small and they share no risky surface.
- **Constrain the pickers, don't move the windows** (chosen over re-deriving windows from the chosen times): morning nudge 05:00–11:45, evening nudge 18:00–23:45. `RitualPolicy.prompt` and its windows stay byte-identical; the nudge always lands inside its window. No new policy edge cases.
- **History = UserDefaults capped array + an evening "Past notes" link** (chosen over a SwiftData model and over a morning "yesterday you said" echo): keeps GOL-85's no-schema stance; device-local is acceptable for a private journal; the list surfaces where the intention already lives (the evening sheet).
- **Hint scoped to the check-in section** — the analogous hint for subscription reminders is noted, not built.

## Components

### 1. Nudge times

**`RitualPolicy` (GoldengoCore)** — pure, tested:
```swift
public static let defaultMorningNudgeMinutes = 8 * 60      // 08:00
public static let defaultEveningNudgeMinutes = 21 * 60     // 21:00
/// Pin a minutes-from-midnight choice inside the morning window (05:00–11:45).
public static func clampMorningNudge(minutes: Int) -> Int   // 300...705
/// Pin a minutes-from-midnight choice inside the evening window (18:00–23:45).
public static func clampEveningNudge(minutes: Int) -> Int   // 1080...1425
```

**`SharedSummary` (GoldengoData)** — minutes-from-midnight as `Int` (no Date/timezone traps):
```swift
ritualMorningMinutesKey / ritualEveningMinutesKey
func setRitualMorningMinutes(_:) / ritualMorningMinutes() -> Int   // default 480 when unset
func setRitualEveningMinutes(_:) / ritualEveningMinutes() -> Int   // default 1260 when unset
```
"Unset" detection via `object(forKey:) == nil` (a stored 0 must not read as midnight-default confusion — clamping also makes 0 impossible).

**`LocalNotificationScheduler.scheduleRitual()`** — reads the two stored minutes (clamped defensively via `RitualPolicy`), `comps.hour = m / 60; comps.minute = m % 60`. Ids unchanged (`ritual:morning`/`ritual:evening`), so re-scheduling replaces.

**`SettingsView`** — when the check-in toggle is ON, two `DatePicker("Morning nudge"/"Evening nudge", displayedComponents: .hourAndMinute)` rows, bound through minutes↔Date conversion on a fixed reference day, with `in:` ranges matching the clamp bounds. Any change → store minutes → `Task { await LocalNotificationScheduler.scheduleRitual() }`.

### 2. Intention history

**`IntentionJournal` (GoldengoCore)** — pure, tested:
```swift
public struct IntentionEntry: Codable, Equatable, Sendable {
    public var date: Date
    public var text: String
}
public enum IntentionJournal {
    public static let capacity = 365
    /// Append, replacing a same-calendar-day entry (editing the morning note never
    /// duplicates) and dropping the oldest beyond `capacity`. Returns newest-LAST.
    public static func append(_ entry: IntentionEntry, to history: [IntentionEntry],
                              calendar: Calendar) -> [IntentionEntry]
}
```

**`SharedSummary`** — one new key `ritualIntentionHistoryKey` holding the JSON-encoded array:
```swift
func readIntentionHistory() -> [IntentionEntry]          // [] when unset/corrupt
func setIntentionHistory(_ entries: [IntentionEntry])
```
`setIntention(_:on:)` additionally runs `setIntentionHistory(IntentionJournal.append(...))` — journaling is automatic, the ritual flow is unchanged.

**`PastNotesView` (GoldengoFeatures)** — a minimal read-only list: dated rows (`date.formatted(.dateTime.day().month().year())` caption + the text), newest first, calm styling per the design system. Reached from **`EveningView`**: below the intention line, a caption-styled "Past notes" button, hidden when history is empty. EveningView is a plain `ScrollView` (no NavigationStack), so the button presents `PastNotesView` as a stacked `.sheet` — one level of sheet-on-sheet, which iOS supports cleanly; device-verified.

### 3. Notifications-off hint

**`LocalNotificationScheduler`**:
```swift
/// True when the user has explicitly denied notification permission.
public static func authorizationDenied() async -> Bool   // getNotificationSettings == .denied;
                                                          // false where UserNotifications is unavailable
```

**`SettingsView`** — in the "Daily check-in" section, shown only when `ritualEnabled && denied`: a footnote-styled line "Notifications are off — check-ins won't nudge you." plus a small "Open iOS Settings" button → `UIApplication.openNotificationSettingsURLString` (`#if os(iOS)`). The denied flag is loaded in `.task` on the sheet's appearance and re-checked when the toggle turns on.

## Data flow

```
Settings: toggle ON → pickers appear (defaults 08:00 / 21:00)
  pick a time → clamp → SharedSummary minutes → scheduleRitual() re-registers both nudges
MorningView Save → setIntention(text, today) → history = IntentionJournal.append(...)
EveningView → intention quote → "Past notes" (if any) → PastNotesView (dated list)
SettingsView appear / toggle-on → authorizationDenied()? → footnote + deep link
```

## Error handling / edge cases

- Stored minutes outside the window (manual defaults tampering, old builds) → clamped at read time by the scheduler; pickers can't produce them.
- Same-day re-save of the intention → history entry replaced, not duplicated.
- Corrupt/undecodable history JSON → `readIntentionHistory()` returns `[]` (journal restarts; the live intention keys are independent and unaffected).
- History at capacity → oldest entry dropped on append (pure, tested).
- Notifications denied while the sheet is open → the hint appears on next Settings open or toggle flip (no live polling; acceptable).
- macOS / no UserNotifications → `authorizationDenied()` is `false`, hint never shows; scheduling stays a no-op.

## Tests

- **`RitualPolicyTests` (GoldengoCoreTests, extend):** clamp passthrough inside the windows; clamping below/above each bound; defaults are inside the windows.
- **`IntentionJournalTests` (GoldengoCoreTests):** plain append; same-day replace (UTC-calendar injected); capacity drop-oldest; Codable round-trip of `IntentionEntry`.
- **`SharedSummary` (GoldengoDataTests, extend):** minutes round-trip + window defaults when unset; history round-trip; corrupt-data → `[]`; `setIntention` appends to history (and same-day re-save keeps one entry).
- **Pickers, scheduler firing times, hint + deep link, PastNotesView** — device-verified.

## Out of scope (explicit)

- Self-presenting windows following the chosen times (windows stay 5–12 / 18–04).
- Syncing intention history across devices (device-local UserDefaults).
- The morning "yesterday you said …" echo.
- A denied-notifications hint for the subscription-reminders section (noted follow-up).
- Editing or deleting individual past notes.
