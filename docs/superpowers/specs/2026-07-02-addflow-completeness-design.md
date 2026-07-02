# Add-flow completeness — design

**Date:** 2026-07-02
**Status:** Approved (sub-project 1 of 3: add-flow → lending → investing)

## Problem

The add flows are missing everyday options:
- No backdating — yesterday's forgotten coffee can only be logged as today's, then
  date-edited from Recent (two extra steps).
- QuickAdd's model already carries `merchant` and `note` and saves them, but the sheet
  never shows the fields.
- The category chips are a hardcoded 7-item list; the user cannot create a category,
  even though the store find-or-creates categories by name on save.

## Decision

Three quiet additions, all in the existing idiom; the 3-second log stays 3 seconds.

1. **Date pill (QuickAdd + AddIncome).** A "When" row: eyebrow label + compact
   `DatePicker` (`displayedComponents: .date`, accent tint), bounded `...now` — future
   entries would corrupt the wallet's expected balance and today's totals. Defaults to
   today; QuickAdd resets it to today after each save.
   - `QuickAddModel`: add `public var date: Date = .now`; `save()` passes it to
     `logManual(date:)`; `reset()` restores `.now`.
   - `SourcesModel.addIncome`: add `date: Date = .now` parameter, forwarded to
     `store.logIncome(date:)` (already exists).

2. **"Add details" (QuickAdd).** A quiet muted text button under the category chips;
   tapping reveals two capsule text fields ("Where?", "Note") bound to the existing
   `model.merchant` / `model.note`. Stays expanded while either field is non-empty.
   Tapping a keypad key clears text-field focus (tap-outside rule; same as AddIncome's
   new-source field).

3. **Create categories (QuickAdd).** A trailing **＋New** chip in the category row opens
   an autofocused capsule name field (the AddIncome new-source pattern). The typed name
   becomes `selectedCategory`; the store's existing find-or-create persists it on save.
   To make created categories reappear:
   - New store API: `recentCategoryNames(limit: Int = 200) -> [String]` — fetch recent
     non-archived expenses (date desc, one bounded fetch), return their distinct category
     names in first-seen order. This IS most-recently-used order, with no schema change.
   - `QuickAddModel.quickCategories` becomes `private(set) var`, loaded on appear:
     recently-used names first, topped up with the current defaults
     (Groceries, Food, Transport, Coffee, Bills, Shopping, Other), deduped
     case-insensitively, capped at 10.

## Testing (intent)

- `recentCategoryNames` returns most-recently-used-first distinct names and skips
  archived expenses (WHY: the chip row is a habit surface — it must reflect what the
  user actually logs, and deleted history must not resurrect chips).
- Backdated `logManual(date:)` behavior is already covered by store tests; the model
  test asserts `save()` forwards the picked date and resets it to today after
  (WHY: a sticky yesterday would silently mis-date every following log).
- Chip merge: user categories before defaults, case-insensitive dedupe, cap 10.

## Out of scope (deferred deliberately)

- History custom date/amount range filters (day/week/month/year browsing covers it).
- Category rename/delete and icons (re-adding covers v1 needs).
- Lending ("owed to you") and investing pots — sub-projects 2 and 3.
