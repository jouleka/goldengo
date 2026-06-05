# GOL-78 — Widget shows stale (yesterday's) today-total

**Ticket:** [GOL-78](https://mysigner.youtrack.cloud/issue/GOL-78).
**Status:** design approved (root cause + fix confirmed with the user); pending spec review.
**Date:** 2026-06-05.
**Depends on:** GOL-68 (`refreshSharedTodayTotal`, widget today-total), GOL-74 (lek→ALL) — shipped.

## Goal

The home-screen widget should show **today's** spending — not yesterday's. It must roll over to the
new day on its own and reflect new expenses (including Apple Pay auto-logs), instead of echoing a
cached value that goes stale at midnight.

## Decision record (root cause + approach)

Root cause (`AppProject/Widget/GoldengoWidget.swift:16-19`): the widget echoes
`SharedSummary.todayTotalText`, a cached string that (1) is only written on log/import
(`refreshSharedTodayTotal`) and **never recomputed at midnight**, so on a new day it still holds
yesterday's total; (2) the widget never recomputes it; (3) only the in-app Add/Import call
`reloadAllTimelines` — the Apple Pay automation path (`LogPaymentIntent → logManual`) doesn't — and
iOS throttles the 15-min auto-refresh.

- **Lightweight fix (chosen):** date-stamp the cached total; the widget shows it only if it's from
  *today*, else 0 in the preferred currency; the timeline rolls over at midnight; and the shared-total
  write path reloads the widget so every log (incl. the automation) refreshes it. No SwiftData access
  from the widget process.
- **Rejected:** widget recomputes today's total from the SwiftData store each refresh — always exact,
  but opens the (CloudKit-configured) store in the widget extension, duplicates `todayTotal` +
  conversion logic, and is riskier/heavier. Not worth it for a "today's spend" glance.
- **Honest limit:** iOS rate-limits widget refreshes, so intra-day "real-time" is best-effort — but
  the widget updates on each log and rolls over at midnight rather than sitting a day stale.

## Components

### 1. `SharedSummary` — date-stamp the total (GoldengoData) — TDD

Add a stored date for the cached total and a date-aware accessor:

```swift
private static let totalDateKey = "todayTotalDate"

public func writeTodayTotal(_ text: String, asOf date: Date = .now) {
    defaults.set(text, forKey: Self.totalKey)
    defaults.set(date, forKey: Self.totalDateKey)
}

/// The total to display *for today*: the cached value if it was computed today, otherwise zero in the
/// preferred currency (a new day with nothing logged yet — or never written).
public func todayDisplayText(now: Date = .now) -> String {
    if let text = defaults.string(forKey: Self.totalKey),
       let date = defaults.object(forKey: Self.totalDateKey) as? Date,
       Calendar.current.isDate(date, inSameDayAs: now) {
        return text
    }
    return Money(amount: 0, currency: readPreferredCurrency()).formatted()
}
```

`writeTodayTotal`'s `asOf` defaults to `.now`, so the existing `refreshSharedTodayTotal` caller stores
the date with no signature change; the `SharedSummaryTests` string round-trip still passes.

### 2. `refreshSharedTodayTotal` reloads the widget (GoldengoData)

`IngestionStore.refreshSharedTodayTotal` (`IngestionStore.swift:91-96`) — after writing the total, also
reload the widget so **every** path that changes the total refreshes it (the previously-uncovered Apple
Pay automation path included):

```swift
#if canImport(WidgetKit)
import WidgetKit   // file-top, guarded
#endif
// …in refreshSharedTodayTotal, after writeTodayTotal:
#if canImport(WidgetKit)
WidgetCenter.shared.reloadAllTimelines()
#endif
```

(`WidgetKit` isn't on macOS, so the guard keeps the CI `swift test` build green.) The existing in-app
`reloadAllTimelines()` calls in `QuickAddModel.save`/`ImportModel` stay — they're now redundant but
benign (iOS coalesces back-to-back reloads); left in place to keep the change surgical.

### 3. Widget — date-aware display + midnight rollover (`GoldengoWidget.swift`)

- `getTimeline`/`getSnapshot` use `SharedSummary().todayDisplayText(now:)` instead of the raw
  `todayTotalText`.
- `getTimeline` returns **two** entries — `(now, todayText)` and `(nextMidnight, zeroText)` — and a
  `.after(nextMidnight)` policy, so the widget rolls to 0 at midnight even if iOS doesn't call
  `getTimeline` exactly then, and regenerates afterward:

```swift
func getTimeline(in c: Context, completion: @escaping (Timeline<GoldengoEntry>) -> Void) {
    let s = SharedSummary(); let snap = s.read(); let now = Date.now
    let zero = Money(amount: 0, currency: s.readPreferredCurrency()).formatted()
    let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                             matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
    let entries = [
        GoldengoEntry(date: now, totalText: s.todayDisplayText(now: now), reveal: snap.revealOnLockScreen),
        GoldengoEntry(date: midnight, totalText: zero, reveal: snap.revealOnLockScreen),
    ]
    completion(Timeline(entries: entries, policy: .after(midnight)))
}
```

- The hardcoded `"L 0"` placeholder becomes `Money(amount: 0, currency: SharedSummary().readPreferredCurrency()).formatted()` (fixes the pre-lek→ALL staleness).

## Data flow

```
log/import/Apple-Pay-tap → logManual/importStatement → refreshSharedTodayTotal
   → writeTodayTotal(text, asOf: now)  [stamps today's date]
   → WidgetCenter.reloadAllTimelines() [every path, incl. the automation]
widget getTimeline → todayDisplayText(now): cached date == today ? cached : 0
   → entries [now: today, midnight: 0], refresh at midnight  →  rolls over on its own
```

## Tests (GoldengoDataTests / SharedSummaryTests — TDD)

- **Today's stamp → shows the cached total.** `writeTodayTotal("ALL 500", asOf: now)`; `todayDisplayText(now:)` == "ALL 500". *Why: a value logged today must show.*
- **Yesterday's stamp → shows 0, not the stale total.** `writeTodayTotal("ALL 500", asOf: yesterday)`; `todayDisplayText(now: today)` == "ALL 0" (lek). *Why: this is the bug — the widget must never show a previous day's total.*
- **Never written → shows 0.** fresh suite → `todayDisplayText()` == "ALL 0". *Why: first run shows a clean zero, not "—".*
- (Uses an isolated `UserDefaults(suiteName:)` like the existing `SharedSummaryTests`; inject `now`/`asOf` for determinism.)

The widget's timeline wiring + midnight rollover are verified by build + on-device (the widget target isn't in `swift test`; WidgetKit timelines are OS-driven).

## Runtime verification

Device: install; confirm the widget shows today's real total (not yesterday's); add an expense (in-app
and via the Apple Pay automation) → widget updates; check it reads 0 after midnight (or simulate by
stamping a past date). Second-Opus review over the diff.

## Out of scope

- Widget recomputing from the SwiftData store (rejected above).
- Beating iOS's widget refresh budget (not possible; documented as best-effort).
- The `accessoryRectangular`/Lock-Screen variants beyond the shared display text (same code path).
