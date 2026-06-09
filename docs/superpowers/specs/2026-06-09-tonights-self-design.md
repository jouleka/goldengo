# GOL-85 — Tonight's Self (morning intention + evening reflection)

**Ticket:** [GOL-85](https://mysigner.youtrack.cloud/issue/GOL-85).
**Status:** design approved; pending spec review.
**Date:** 2026-06-09.
**Origin:** standout #4b — second of the **Re-entry (GOL-84) + Tonight's Self** bundle.
**Builds on:** `LocalNotificationScheduler`/`SubscriptionReminderPlanner` (notification glue), `SharedSummary` (UserDefaults), `RootView` scenePhase wiring (incl. Re-entry/GOL-84), GOL-82 `rhythmGhosts`/`confirmRhythmGhost`, `SettingsView`.

## Goal

A same-day self-continuity ritual: in the morning you write one intention ("a letter from this-morning-you"); at night a calm "close the day" reflection surfaces it back, confirms today's usuals, shows a gentle spend recap, and closes affirmingly. Opening it at night should feel like a note from someone who was rooting for you — accountability to *yourself*, not a budget scolding.

## Decision record (brainstorm)

- **Scope = FULL morning + evening** (chosen over evening-only and over evening-with-note). Two touchpoints: a morning intention capture + an evening reflection that surfaces it.
- **Opt-in, self-presenting.** A Settings toggle enables it (requests notification auth + schedules two daily nudges); the screens **self-present on app open in the right time window via `scenePhase`** (the Re-entry pattern) — so a notification tap just brings you in. **No `UNUserNotificationCenterDelegate`** → no app-target file → no `project.rb` regen.
- **`.sheet`, not `.fullScreenCover`** — cross-platform (avoids the iOS-only guard that bit GOL-84) and lighter than the Re-entry takeover.
- **Re-entry takes precedence** — if the gap soft-landing presents on an activation, the ritual is skipped that activation.
- **Storage in `SharedSummary` (UserDefaults), no SwiftData model** — no schema migration.

## Components

### 1. `RitualPolicy` — `Sources/GoldengoCore/RitualPolicy.swift` (pure, the tested core)
```
public enum RitualPrompt: Sendable, Equatable { case morning, evening, none }
public enum RitualPolicy {
    public static let morningHours = 5..<12     // local-hour window
    public static let eveningStartHour = 18     // 18:00 .. 04:00 next day
    public static let eveningEndHour = 4
    public static func prompt(now: Date, intentionDate: Date?, reflectedDate: Date?,
                              calendar: Calendar = .current) -> RitualPrompt
}
```
Logic: let `hour = calendar.component(.hour, from: now)`. **Morning** if `morningHours.contains(hour)` and `intentionDate` is not the same calendar day as `now` → `.morning`. Else **evening** if (`hour >= eveningStartHour || hour < eveningEndHour`) and `reflectedDate` is not the same day as `now` → `.evening`. Else `.none`. Uses `calendar.isDate(_:inSameDayAs:)` for "today" checks (local calendar — the user's day). Pure, no persistence/UI.

### 2. `SharedSummary` keys (GoldengoData, UserDefaults — no migration)
```
ritualEnabledKey, intentionKey, intentionDateKey, reflectedDateKey
func setRitualEnabled(_:) / ritualEnabled() -> Bool
func setIntention(_ text: String, on: Date)  // stores text + date
func readIntention() -> (text: String, date: Date)?
func setReflected(on: Date) / readReflectedDate() -> Date?
```

### 3. `LocalNotificationScheduler` — add ritual scheduling (GoldengoFeatures)
```
static func scheduleRitual() async   // two daily repeating triggers, prefix "ritual:"
static func cancelRitual() async
```
Morning: `UNCalendarNotificationTrigger(hour: 8, minute: 0, repeats: true)` — title "Set today's intention". Evening: `hour: 21` — title "Close your day". `#if canImport(UserNotifications)` (no-op macOS). Mirrors the existing `sync`/`cancelAll` prefix-filtering pattern (so it never disturbs `sub-reminder:` requests).

### 4. Screens (GoldengoFeatures, `.sheet`)
- **`MorningView`** — "What's today about?" a single-line `TextField` + **Save** (→ `setIntention(text, on: .now)`) and a **Skip** (dismiss without storing). Calm, minimalist; keyboard dismissal per conventions.
- **`EveningView` + `EveningModel` (@MainActor @Observable)** — `EveningModel` loads on appear: today's `rhythmGhosts`, today's total (`todayTotal`), and the morning intention (if `intentionDate` is today). View shows: *"This morning you said: \(intention)"* (or a gentle "No note this morning — that's fine."), the **usuals** as one-tap confirm rows (reusing `confirmRhythmGhost`), the calm today's-spend line, and a warm close ("You were trying. Rest well.") with **Done** → `setReflected(on: .now)` + dismiss.

### 5. `RootView` wiring
- State: a wrapper `struct RitualSheet: Identifiable { let id = UUID(); let kind: RitualPrompt }` (the `RitualPrompt` enum isn't `Identifiable`) + `@State private var ritualSheet: RitualSheet?`.
- A `checkRitual()` helper: `guard reEntryPrompt == nil else { return }` (Re-entry precedence); `guard SharedSummary().ritualEnabled() else { return }`; compute `RitualPolicy.prompt(now:, intentionDate:, reflectedDate:)`; if `.morning`/`.evening`, set `ritualSheet`.
- Call `checkRitual()` right after `checkReEntry()` in BOTH the cold-launch `.task` and `.onChange(scenePhase) == .active`.
- `.sheet(item: $ritualSheet) { s in if s.kind == .morning { MorningView(onDone: { ritualSheet = nil }) } else { EveningView(model: EveningModel(store: store), onDone: { ritualSheet = nil }) } }`.

### 6. `SettingsView` — "Daily check-in" toggle
A `Section`/toggle mirroring the existing subscription-reminder toggle: bound to `ritualEnabled`; on enable → `Task { await LocalNotificationScheduler.requestAuthorization(); await LocalNotificationScheduler.scheduleRitual() }`; on disable → `Task { await LocalNotificationScheduler.cancelRitual() }`. Default **off**.

## Data flow
```
Settings toggle ON → request auth + scheduleRitual() (8am + 9pm daily nudges)
morning open (5–12h, no intention today) → MorningView → setIntention(text, today)
evening open (18–4h, not reflected today) → EveningView:
    load rhythmGhosts + todayTotal + today's intention
    show "this morning you said …" + confirm usuals + spend recap + warm close
    Done → setReflected(today)
RootView .active/.task → checkReEntry() (precedence) → else checkRitual() → present the right sheet once/day
toggle OFF → cancelRitual()
```

## Error handling / edge cases
- Notifications denied → `scheduleRitual` is a best-effort no-op; the toggle stays on but nudges won't fire (the screens still self-present on open). (A "notifications are off" hint is a noted follow-up.)
- No intention set today → evening shows the gentle "no note" line, not an empty quote.
- Re-entry + ritual both eligible on one activation → Re-entry wins (ritual skipped that activation).
- Once-per-day each: `intentionDate`/`reflectedDate` same-day checks prevent re-presenting after completion; Skip (morning) does NOT set `intentionDate`, so it may re-prompt later that morning — acceptable (or set a "skipped today" marker; v1 keeps it simple and just won't store an intention).
- macOS / non-UserNotifications → scheduling is a no-op; policy + screens still compile (`.sheet` cross-platform).

## Tests
- **`RitualPolicyTests` (GoldengoCoreTests) — the core:** morning window + no-intention-today → `.morning`; intention already set today → not morning; evening window + not-reflected → `.evening`; reflected today → `.none`; midday/out-of-window → `.none`; evening wrap-around hours (e.g. 23h and 1h) → evening; boundary hours. (Inject `now` + a fixed `calendar`.)
- **`SharedSummary` (GoldengoDataTests):** intention text+date and reflectedDate and ritualEnabled round-trip; `readIntention` nil when unset.
- **`EveningModel` (GoldengoFeaturesTests):** loads ghosts + today total + today's intention against an in-memory store; confirming a usual logs it.
- **Notifications / screens / scenePhase** — device-verified (UNUserNotificationCenter + visual + lifecycle).

## Out of scope (explicit, v1)
- User-customizable notification times (fixed 8am/9pm; a time picker is a follow-up).
- Intention history / a journal of past days (only today's intention is stored).
- Streaks, scores, or any gamification.
- A morning ghost/usuals preview (usuals are an evening thing).
- A "notifications are disabled — enable in Settings" remediation hint.
- The Re-entry feature itself (shipped as GOL-84).
