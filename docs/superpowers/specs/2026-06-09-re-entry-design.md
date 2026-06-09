# GOL-84 — Re-entry (gentle soft-landing after a gap)

**Ticket:** [GOL-84](https://mysigner.youtrack.cloud/issue/GOL-84).
**Status:** design approved; pending spec review.
**Date:** 2026-06-09.
**Origin:** standout #4a (the abandonment-killer) from the ultracode ideation — first of the **Re-entry + Tonight's Self** bundle, built as its own cycle.
**Builds on:** `SharedSummary` (App-Group UserDefaults), `RootView`'s `scenePhase` handling, the design system.

## Goal

The #1 reason people abandon expense trackers is the wall of guilt waiting when they come back. Re-entry makes the return the **warmest** screen in the app: reopen after being away and you get a single calm acknowledgment — "Welcome back, it's been X days, that stretch is behind you, nothing's assumed. Here's today." — and one tap to continue. **No catch-up homework, no guilt.**

## Decision record (brainstorm)

- **Scope = warm acknowledgment + re-anchor ONLY** (chosen over "+ offer gap-due recurring charges" and over a "full gap summary"). The warmth *is* the feature; it's the differentiated, minimal core with zero overlap with the Subscriptions feature. A full gap summary would risk becoming the exact wall-of-homework the feature exists to avoid. (Offering gap-due recurring charges is a noted fast-follow.)
- **Gap measured via `SharedSummary.lastSeen`**, set on `.background`, checked on `.active`. First launch (no `lastSeen`) and same-day reopens never trigger.
- **Threshold ≥ 4 days** (a long weekend doesn't trigger; a week away does) — a tunable constant.
- **Pure decision logic** (`ReEntryPolicy`) so the trigger is unit-tested; the screen + scenePhase wiring are device-verified.

## Components

### 1. `SharedSummary` — add last-seen (GoldengoData)
```
public static let lastSeenKey = "lastSeen"
public func setLastSeen(_ date: Date = .now) { defaults.set(date, forKey: Self.lastSeenKey) }
public func readLastSeen() -> Date? { defaults.object(forKey: Self.lastSeenKey) as? Date }
```

### 2. `ReEntryPolicy` — pure decision (GoldengoCore)
```
public enum ReEntryPolicy {
    public static let thresholdDays = 4
    /// Whole days away, or nil if there's no prior session or the gap is non-positive (same-day / clock skew).
    public static func daysAway(lastSeen: Date?, now: Date = .now) -> Int?
    /// True when a soft-landing should show.
    public static func shouldShow(lastSeen: Date?, now: Date = .now) -> Bool
}
```
`daysAway` uses a UTC `Calendar` `dateComponents([.day], from: lastSeen, to: now)`; returns nil if `lastSeen == nil` or the day count `<= 0`. `shouldShow` = `(daysAway ?? 0) >= thresholdDays`.

### 3. `ReEntryView` — the soft landing (GoldengoFeatures)
A single calm screen (presented as a `.fullScreenCover`): a gentle icon (e.g. `sunrise`/`leaf`), a warm headline ("Welcome back"), one line — *"It's been \(days) days — that stretch is behind you. Nothing's assumed."* — and one primary button **"Here's today"** that dismisses. No data entry, no list of missed items. Takes `daysAway: Int` + `onContinue: () -> Void`. Minimalist, calm; built with the frontend-design skill.

### 4. `RootView` wiring (GoldengoFeatures)
- A small `Identifiable` wrapper `struct ReEntryPrompt: Identifiable { let id = UUID(); let days: Int }` and `@State private var reEntryPrompt: ReEntryPrompt?` (drives a `.fullScreenCover(item:)`, since `Int?` isn't directly `Identifiable`).
- In `.onChange(of: scenePhase)`:
  - `.background` → `SharedSummary().setLastSeen()`.
  - `.active` → existing reload, **plus**: `if let d = ReEntryPolicy.daysAway(lastSeen: SharedSummary().readLastSeen()), d >= ReEntryPolicy.thresholdDays { reEntryPrompt = .init(days: d) }`, then `SharedSummary().setLastSeen()` (reset so it won't re-fire this session).
- `.fullScreenCover(item: $reEntryPrompt) { p in ReEntryView(daysAway: p.days) { reEntryPrompt = nil } }`.
- First-ever launch (no `lastSeen`) shows nothing (`daysAway` is nil), and `checkReEntry`'s unconditional `setLastSeen()` tail seeds the baseline. That reset is **load-bearing** — it makes any later same-session `.active` a 0-day no-op — and a `reEntryPrompt == nil` guard additionally makes a re-present impossible regardless of `.task`/`.onChange` fire ordering.

## Data flow
```
app backgrounded → SharedSummary.setLastSeen(now)
app foregrounded (.active) → daysAway = ReEntryPolicy.daysAway(lastSeen, now)
    → if daysAway >= 4: present ReEntryView(daysAway)   (warm screen, one button)
    → setLastSeen(now)   (reset; won't re-fire until the next real gap)
tap "Here's today" → dismiss → Home, today's data already loaded
```

## Error handling / edge cases
- No `lastSeen` (first ever launch) → `daysAway` nil → no landing; baseline seeded on first appear/background.
- Same-day reopen / background-foreground within the day → day count 0 → no landing.
- Clock moved backwards (negative gap) → non-positive day count → nil → no landing (never show a nonsensical "−2 days").
- Multiple `.active` in one session → after the first shows + resets `lastSeen` to now, subsequent gaps are ~0 → no re-fire.

## Tests
- **`ReEntryPolicyTests` (GoldengoCoreTests):** `daysAway` returns the correct whole-day count; `nil` when `lastSeen == nil`; `nil`/no-show for same-day and future `lastSeen`; `shouldShow` boundary — 3 days → false, 4 days → true.
- **`SharedSummary` (GoldengoDataTests):** `lastSeen` set → read round-trips; unset → `nil`.
- **`ReEntryView` + scenePhase wiring:** device-verified (visual + lifecycle).

## Out of scope (explicit, v1)
- Offering gap-due recurring charges to add (overlaps Subscriptions; noted fast-follow).
- Any gap summary / stats / "days missed" framing beyond the single warm line.
- Streaks, re-engagement nudges, or notifications (that's the sibling feature, Tonight's Self).
- Per-user-tunable threshold UI (it's a constant in v1).
