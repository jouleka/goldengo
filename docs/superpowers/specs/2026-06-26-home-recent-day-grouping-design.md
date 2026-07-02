# Home "Recent" — group by day, collapsible

**Date:** 2026-06-26
**Status:** Implemented (test-first) on branch `home-recent-day-grouping` — awaiting on-device sign-off
**Scope:** `RecentExpensesView` (view layer) + one pure helper on `RecentExpensesModel` + a unit test. No data-layer change.

## Problem

Home is both the dashboard *and* the full ledger. The "Recent" section
([`RecentExpensesView.swift`](../../../Sources/GoldengoFeatures/Recent/RecentExpensesView.swift)
lines 69–76) renders a flat, ungrouped, reverse-chronological list of up to 50 expenses
(`all.prefix(50)` in
[`IngestionStore+HomeData.swift`](../../../Sources/GoldengoData/IngestionStore+HomeData.swift) line 55),
stacked under the hero / Upcoming / Today's usuals.

There is no day grouping, no orientation, and no way to shorten the run. The user's words:
"if it becomes too big we can't see the last items and we just keep scrolling and scrolling —
there has to be a better way, more logical." Two distinct pains hide in that sentence:

1. **Disorientation** — a featureless wall of near-identical rows; you lose track of *when*.
2. **Length** — too far to scroll to reach older items.

## Decision

Group the Recent rows **by calendar day**, with **sticky day headers** (fixes #1) and
**collapsible day sections** (fixes #2). Confirmed direction: keep everything on Home — no
second/History screen.

Rejected alternatives (and why):
- **Glance + separate History screen** — cleanest IA, but the user wants the full list to stay
  on Home, not behind a tab/push.
- **Collapse-by-default ("Show earlier")** — hides rows until tapped; the user preferred everything
  visible by default. Our collapse is *opt-in* (expanded by default), which keeps that property.
- **Per-day money subtotals** — deliberately excluded. The 50-row cap can truncate the oldest day,
  so its subtotal would be wrong/misleading. Grouping stays purely structural. (A per-day **count**
  is shown — a truncated count is far less misleading than truncated money, and it tells you what a
  *collapsed* day holds.)

## Design

### 1. Grouping — pure and testable

A pure function on the model (not inline in `body`), so a unit test can lock its behavior
independent of SwiftUI:

```swift
public struct DayGroup: Identifiable, Equatable {
    public let id: Date          // start-of-day, stable bucket key
    public let title: String     // "Today" / "Yesterday" / "Mon 23 Jun"
    public let rows: [ExpenseSnapshot]
}

extension RecentExpensesModel {
    /// Bucket already-newest-first rows into calendar days, preserving order so the result is
    /// day-descending (Today first). `now` drives the relative "Today"/"Yesterday" labels.
    public nonisolated static func dayGroups(from rows: [ExpenseSnapshot],
                                             now: Date,
                                             calendar: Calendar = .current) -> [DayGroup]
}
```

- Input rows are already `date`-descending (Home fetch sorts that way). Bucket by
  `calendar.startOfDay(for: row.date)`, preserving first-seen order → groups come out
  newest-day-first.
- `title`: the day is compared against `startOfDay(now)` and the day before it (computed from the
  injected `now`, *not* `Calendar.isDateInToday`, which reads the system clock and isn't testable) →
  "Today" / "Yesterday"; else a locale-formatted short date, e.g.
  `day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))`.
- `nonisolated static` + injectable `calendar` so tests can pin a timezone/locale and feed a fixed `now`.

### 2. View — sections, sticky headers, collapse

The flat `ForEach(model.rows)` becomes a loop over `dayGroups`, each a real `Section` so iOS pins
its header during scroll under `.listStyle(.plain)` (already set, line 78):

```swift
// Derived each body pass from model.rows via the pure helper; .now drives relative labels.
ForEach(RecentExpensesModel.dayGroups(from: model.rows, now: .now)) { group in
    Section {
        if !collapsedDays.contains(group.id) {
            ForEach(group.rows, id: \.dedupeKey) { r in recentRow(r) }
        }
    } header: {
        dayHeader(group)                       // tappable; toggles collapse
    }
}
```

- The existing big serif **"Recent"** title (line 70–71) stays as a plain leading row — it scrolls
  away; only the lighter **day** headers stick. That gives the hierarchy: *area title* → *running day index*.
- `recentRow`, the leading/trailing swipe actions, tap-to-edit, and the Undo toast are unchanged —
  rows are just nested under sections.

### 3. Day header

- Layout: title (small, muted) · row **count** · `Spacer` · chevron.
- Style: a quiet sub-level, not a peer of the serif "Recent" — small caps/medium weight, `inkMuted`,
  with the design system's hairline. Reuses `goldengoCardRow`-style insets / clear background /
  hidden separators so it sits flush in the plain List like the existing cards.
- Chevron: `chevron.down` expanded, rotates to `chevron.right` when collapsed.
- Whole header is the tap target → toggles `collapsedDays` inside `withAnimation(.snappy)`.
- Accessibility: header is one element; label reads e.g. "Yesterday, 4 expenses, expanded — double tap to collapse".

### 4. Collapse state

```swift
@State private var collapsedDays: Set<Date> = []   // start-of-day keys; membership = collapsed
```

- **Expanded by default** (empty set).
- **Keyed by start-of-day Date**, not list index → survives the frequent `model.load()` reloads
  (tab return, scenePhase `.active`, after add/edit/delete). A day you fold stays folded after you
  log a new expense today.
- **Session-only** — not persisted to disk. Resets on relaunch. (YAGNI: lightweight UI state.)

## Edge cases

- **Empty Recent** → existing `emptyRecentCard` unchanged (no groups to render).
- **50-row cap** → unchanged; still the Home horizon. The oldest day may be partial (the tail of that
  day) — this is why subtotals are omitted; the count may also be partial but is acceptable.
- **All rows same day** → one "Today" section; collapsing it hides the whole Recent list (acceptable;
  the header + count remain).
- **Locale/timezone** → day bucketing and labels use the injected `Calendar` (default `.current`);
  date format is locale-driven.
- **Mixed kinds** (income / transfer / expense) → grouping is by day only; row rendering is unchanged,
  so kinds keep their existing per-row treatment.

## Testing (Rule 9 — encode *why*)

Unit test for `dayGroups(from:now:calendar:)` using a fixed `calendar`/`now`:

1. **Ordering** — newest day first; rows within a day stay newest-first. *Why:* the user scans
   top-down expecting most-recent-first; a regression that re-sorts breaks orientation.
2. **Bucketing across a day boundary** — two rows minutes apart but on different calendar days land in
   different groups. *Why:* "23:59 vs 00:01" must read as two days, not one.
3. **Relative labels** — today→"Today", yesterday→"Yesterday", older→explicit date. *Why:* the relative
   labels are the orientation payload; a test that can't fail when label logic changes is worthless.
4. **Empty input** → `[]`.

Collapse is view `@State` (set membership toggle); its correctness is trivial and verified on-device
rather than via a UI test — consistent with the project's "see the UI on a real device early" gate.

## Out of scope

- Raising the 50-row cap / showing full history beyond 50 (separate concern).
- Per-day money subtotals.
- A dedicated History screen / search / month jump.
- Persisting collapse state across launches.

## Verification

`swift test` (the SPM library + tests build; the app target's Plaid block doesn't affect this).
Then on-device: confirm sticky headers pin correctly, collapse animates, swipe/edit/undo still work.
