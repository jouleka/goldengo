# History — period browser (Day / Week / Month / Year)

**Date:** 2026-06-26
**Status:** Implemented + adversarially reviewed (two rounds) on branch `home-recent-day-grouping` — awaiting on-device sign-off

**Review resolutions:** parity test re-encoded to the month-scope intent; Home reloads on pop-back from
History; `appear()` lands on the current period (kills stale launch anchor + currency staleness);
day/week period labels now carry the year when not in the current year (and both years across a year
boundary); the custom tab bar is hidden while History is pushed (it's a ZStack sibling, not a real tab
bar). Accepted as v1 scope: single-slot undo (deletes are reversible), and History rows omit the
funded-by chip / source-pin picker.

**v1 behavior notes (open for on-device feedback):**
- Opening History lands on the current period (preserving the chosen Day/Week/Month/Year scale) — it
  doesn't resume a previously-browsed past period. This avoids a stale launch-time anchor and means a
  currency change made while History was closed is always reflected on the next open.
- The History edit sheet hides the "Paid from" source-pinning picker (passes no funding sources). Editing
  amount/merchant/category/date/note works; only source-pinning is Home-only in v1.
**Builds on:** the day-grouping/collapse work in the same branch.

## Problem

Home shows only the most-recent activity and there is no other screen, so anything older is
invisible everywhere in the app. The user wants a Whoop-style browser: a toggle at the top that
switches granularity (Day / Week / Month / Year) and steps through time, surfacing *all* expenses for
the chosen period. Home itself should feel fresh each month ("start from scratch"); the past lives in
History.

Hard requirement: **fast and reliable.** Period math must be correct across week-start locales, month
lengths, leap years, DST, and year boundaries; fetches must stay cheap; nothing may regress.

## Decisions (confirmed)

1. **Placement** — History is a screen *pushed from Home* (Home already owns a `NavigationStack`).
   Entry: a `See all ›` affordance on Home's "Recent" header. The minimal Home · ⊕ · Wallet bar is
   untouched.
2. **Home resets monthly** — Home's "Recent" list shows only the current calendar month, day-grouped
   (as just built). Everything older is reached via History.
3. **v1 is lean** — period total + expense count + the grouped, collapsible list. No charts or
   category breakdown yet.

## Architecture

Three layers, each independently testable. Reuses the existing date-predicate fetch pattern,
`CurrencyConverter`, `makeSnapshot`, and the `dayGroups`/collapse view code.

### 1. Period math — pure, in `GoldengoCore` (the reliability core)

```swift
public enum PeriodScale: String, CaseIterable, Sendable, Identifiable {
    case day, week, month, year
    public var id: String { rawValue }
    public var title: String   // "Day" / "Week" / "Month" / "Year"
}

public struct PeriodRange: Equatable, Sendable {
    public let start: Date   // inclusive
    public let end: Date     // exclusive  → half-open [start, end)
    public func contains(_ date: Date) -> Bool   // start <= date < end
}

extension PeriodScale {
    /// The [start, end) period of this scale containing `date`. Delegates to
    /// `Calendar.dateInterval(of:for:)` — which already handles first-weekday, month length, leap
    /// years, and DST — so we never hand-roll boundary arithmetic.
    public func range(containing date: Date, calendar: Calendar = .current) -> PeriodRange

    /// Move the anchor by `steps` whole units (negative = into the past).
    public func anchor(_ date: Date, steppedBy steps: Int, calendar: Calendar = .current) -> Date

    /// Human label for a range. day → "Today"/"Yesterday"/"Jun 26"; week → "This week"/"Jun 22 – 28";
    /// month → "June 2026"; year → "2026". `now` drives the relative words.
    public func label(for range: PeriodRange, now: Date,
                      calendar: Calendar = .current, locale: Locale = .current) -> String
}

/// You may step forward only while the shown period has fully ended — i.e. there is a real
/// past/present period to move to. Viewing the current period (now ∈ [start,end)) disables "next",
/// so the user can never browse into the future.
public func canStepForward(from range: PeriodRange, now: Date) -> Bool   // range.end <= now
```

All of the above is unit-tested hard: week start respects `calendar.firstWeekday`; ranges are correct
at month/year boundaries, across a leap day, and across a DST transition; `anchor(steppedBy:)` crosses
month/year boundaries correctly; `canStepForward` is false on the current period and true on a past
one; labels produce the relative words only when appropriate.

### 2. Data layer — `IngestionStore.historyData(...)`

```swift
public struct HistorySnapshot: Sendable, Equatable {
    public let scale: PeriodScale
    public let range: PeriodRange
    public let totalSpent: Decimal      // expense-kind only, in displayCurrency
    public let expenseCount: Int        // expense-kind rows in range
    public let rows: [ExpenseSnapshot]  // ALL kinds in range, date-desc (income/transfer render as today)
    public let ratesAsOf: Date?         // set when any conversion happened
}

extension IngestionStore {
    public func historyData(scale: PeriodScale, anchor: Date,
                            displayCurrency: CurrencyCode, rates: RateTable,
                            now: Date = .now) throws -> HistorySnapshot
}
```

- Computes `range = scale.range(containing: anchor)`.
- Fetches non-archived rows with `date >= range.start && date < range.end`, sorted date-desc. **Only a
  date predicate — never Decimal** (the `#Predicate` Decimal segfault does not apply).
- `totalSpent` / `expenseCount` reduce the expense-kind rows in memory via `CurrencyConverter`
  (same pattern as `makeDashboardSummary`).
- Rows built with the existing `makeSnapshot`. No provenance/funding-label work in History v1 (that's
  a Home-dashboard nicety and an extra cost) — keeps each period load cheap.

Each load touches only one period's worth of rows: Day/Week/Month are tiny; Year is one bounded year.

Added to the `RecentExpensesReading` protocol so the view model can be tested against a fake reader.

### 3. View model — `HistoryModel` (`@MainActor @Observable`, in `GoldengoFeatures`)

State: `scale`, `anchor`, `currency`, `snapshot?`, `loadFailed`. Methods: `load()`,
`setScale(_:)` (resets anchor to `.now`), `stepBackward()`, `stepForward()` (guarded by
`canStepForward`), and computed `canStepForward`, `periodLabel`, `dayOrMonthGroups`. Navigation keeps
the previously-loaded snapshot on screen until the new one arrives — no blank flash.

### 4. View — `HistoryView` (`GoldengoFeatures`)

Top→bottom: a custom segmented control (`Day · Week · Month · Year`, gold selected pill on the bone
field — the native segmented control is off-brand); a period stepper `‹ label ›` with the forward
chevron disabled when `!canStepForward`; a `SPENT …` summary with total + count; then the grouped,
collapsible `List` — grouped by **day** for day/week/month, by **month** for year. Rows reuse the
existing row look; tap → `EditExpenseView`; swipe → delete-with-undo (same as Home).

Grouping generalizes the existing helper: keep `dayGroups`, add a sibling `monthGroups(from:now:)`
(buckets by start-of-month, labels "This month"/"June"/"June 2025"). `HistoryModel` picks which to use
from `scale`.

### 5. Home changes (minimal)

- `homeData`: the Recent `rows` change from `all.prefix(50)` to the current calendar month
  (`date >= monthStart`), still date-desc. The broader `all` fetch (needed for ghosts/provenance)
  is unchanged — only which rows feed the list changes.
- Add a `See all ›` button on the "Recent" section header that pushes `HistoryView`.

## Testing (Rule 9 — encode *why*)

- **Period math** (the bulk): boundaries, leap day, DST, week-start locale, anchor stepping across
  month/year, `canStepForward` current-vs-past, relative labels. *Why:* this is the reliability
  surface; a silent off-by-one here misfiles a user's whole month.
- **`historyData`**: a row just inside vs. just outside the range boundary (inclusive start, exclusive
  end); `totalSpent` counts expenses only (income/transfer excluded) and converts currency;
  `expenseCount` matches; empty period → zeroes + `[]`. *Why:* the boundary and the
  expense-only total are exactly what a user would notice is wrong.
- **`monthGroups`**: ordering newest-month-first, relative "This month" label. (Mirrors the existing
  `dayGroups` tests.)
- **`HistoryModel`**: `setScale` resets anchor to now; `stepForward` is a no-op when `!canStepForward`;
  step then load requests the right range. Tested against a fake reader.

## Out of scope (v1)

Charts / category breakdown; swipe-paging between periods (chevrons only — robust first); search;
History as a bottom-bar tab; funding-label chips in History rows; raising any cap (History is the cap
relief). A SwiftData date index is deferred — personal-scale data scans fast; revisit if it grows.

## Verification

`swift test` (full suite stays green). On-device: toggle across all four scales, step back through
several periods and confirm totals/labels, confirm "next" disables on the current period, confirm
edit/delete/undo work in History and that Home now shows only the current month with a working
`See all`.
