# GOL-70 + GOL-71 — Richer, minimal expense details (description / note)

**Tickets:** [GOL-70](https://mysigner.youtrack.cloud/issue/GOL-70) (Quick Add: optional description at add time) and [GOL-71](https://mysigner.youtrack.cloud/issue/GOL-71) (Edit: richer details + show description in the Recent row), subtasks of epic [GOL-64](https://mysigner.youtrack.cloud/issue/GOL-64).
**Status:** design approved; pending spec review.
**Date:** 2026-06-03.
**Depends on:** nothing new — `ExpenseRecord.note` already exists.

## Goal

Let the user label an expense with a short **note** ("what was paid for", e.g. "lunch with Ana",
"AWS bill") — primarily **at add time** on the Quick Add keypad screen, and more fully on **edit** —
without adding screens, taps, or anything to think about. Surface the note in the Recent row so the
list reads as *what* was bought, not just the merchant/category.

## Decision record

- **New `note` is the surfaced field; `merchantName` stays separate (edit-only).** The single field
  shown at add time is the free-text note, persisted to the **already-existing** `ExpenseRecord.note`
  column. `merchantName` remains a structured field edited only in `EditExpenseView`, and it keeps
  driving subscription detection (merchant+currency grouping) — so freeform notes never pollute
  subscription grouping, and manual Quick Adds still create no auto-subscriptions (status quo).
  *(Chosen over reusing `merchantName` as the description, and over two visible fields at add time.)*
- **One field at add time, both at edit time.** Quick Add shows one optional note row; Edit shows
  merchant **and** note. This reconciles GOL-70 (one field, low-tap) with GOL-71 (note alongside
  merchant). Matches the epic's "a single optional description is enough for v1" for the add path.
- **Always-visible note row on Quick Add**, placed between the amount and the category chips — not a
  hidden affordance and not a follow-up sheet. Zero taps to discover, one tap to use; the common
  no-note case ignores it entirely.
- **No migration.** `ExpenseRecord` already declares `merchantName: String?` *and* an unused
  `note: String?` ([ExpenseRecord.swift:10-11](../../../Sources/GoldengoData/Models/ExpenseRecord.swift)),
  and the initializer already accepts `note`. Today `note` is dead: absent from `ExpenseSnapshot`,
  `logManual`, `updateExpense`, and every screen. This work wires it through.
- **Recent row leads with the note.** Primary text precedence becomes `note ?? merchant ?? category`.
  When a note *and* merchant both exist, the row shows the note and the merchant appears only in Edit
  — keeping the row to one clean line. Secondary text (category) is unchanged.
- **Empty/whitespace normalizes to `nil`.** Both the add and edit paths trim and store `nil` for a
  blank note, so the Recent row falls back cleanly instead of rendering an empty line, and a cleared
  note on edit becomes `nil` (not `""`).
- **`displayTitle` helper.** The `note ?? merchant ?? category ?? "Expense"` precedence is extracted
  to a computed property on `ExpenseSnapshot`, so it is unit-testable and the two call sites I am
  already editing (Recent row + Undo toast) share one definition.

## Components

### 1. `ExpenseSnapshot.note` + `makeSnapshot` (GoldengoData)

`ExpenseSnapshot` ([IngestionStore.swift:7-20](../../../Sources/GoldengoData/IngestionStore.swift))
gains `public var note: String?`. `makeSnapshot(_:)` (lines 98-103) passes `r.note` so the note
crosses the actor boundary to the UI. This is the only reason the Recent row and Edit view can see
the note.

### 2. `logManual` note parameter (GoldengoData)

`logManual` ([IngestionStore.swift:119-137](../../../Sources/GoldengoData/IngestionStore.swift)) gains
`note: String? = nil` (defaulted so `GoldengoIntents`/`GoldengoImport`/existing tests keep compiling).
The new record stores the trimmed note, empty → `nil`:

```swift
let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
// ... record.note = (cleanNote?.isEmpty ?? true) ? nil : cleanNote
```

`merchant:` is untouched.

### 3. `updateExpense` note parameter (GoldengoData)

`updateExpense`
([IngestionStore+Editing.swift:28-44](../../../Sources/GoldengoData/IngestionStore+Editing.swift))
gains `note: String? = nil`, normalized the same way the existing `merchant` handling does
(`r.note = (trimmed?.isEmpty ?? true) ? nil : trimmed`) and bumps `updatedAt`. Lets Edit both set and
clear a note.

### 4. `ExpenseSnapshot.displayTitle` (GoldengoData)

```swift
public var displayTitle: String { note ?? merchantName ?? categoryName ?? "Expense" }
```

Encodes "lead with what was bought." Replaces the inline `merchantName ?? categoryName ?? "Expense"`
at the Recent row and Undo toast. Pure, unit-tested.

### 5. `QuickAddModel.note` (GoldengoFeatures)

Add `public var note: String = ""` (mirrors `merchant` at
[QuickAddModel.swift:16](../../../Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift)). `save()`
(lines 71-73) passes `note: note.isEmpty ? nil : note` to `logManual`; `reset()` (line 86) clears it.
`merchant` stays `""` (still not surfaced in Quick Add) → no behavior change to subscriptions.

### 6. Quick Add note row + keyboard flow (GoldengoFeatures, `QuickAddView`)

Insert an always-visible note row between `amountDisplay` and `categoryChips`
([QuickAddView.swift:20-27](../../../Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift)): a
`TextField("Add a note (optional)", text: $model.note)` in a `GoldengoTheme` field-background rounded
rect (Spacing/Radius tokens), single line, small leading glyph, low emphasis. Keyboard handling:

- `@FocusState private var noteFocused: Bool` + `.focused($noteFocused)`.
- `.submitLabel(.done)` and `.onSubmit { noteFocused = false }` so Return dismisses the keyboard back
  to the keypad + Add button.
- An iOS-only keyboard toolbar "Done" as a backup dismissal.
- iOS-only modifiers (`.keyboardType`, `.toolbar(placement: .keyboard)`) guarded with
  `#if canImport(UIKit)` per the CI/macOS constraint (GoldengoFeatures compiles on macOS in CI).

Flow: amount on the keypad → (optionally) tap the note row → type → Return → keypad + Add reappear →
Add. The no-note case is unchanged (zero extra taps). Visual polish via `/frontend-design`.

### 7. Edit note field + update path (GoldengoFeatures, `EditExpenseView`)

Add `@State private var note: String` (init from `snap.note ?? ""`) and a
`TextField("Note (optional)", text: $note)` alongside the existing merchant field
([EditExpenseView.swift:104-108](../../../Sources/GoldengoFeatures/Recent/EditExpenseView.swift)).
Extend the `onSave` closure to carry the note (`{ amt, m, n, c, d in ... }`, line 73) and
`RecentExpensesModel.update(_:amount:merchant:note:categoryName:date:)` to forward it to
`updateExpense(... note:)`.

### 8. Recent row + Undo toast (GoldengoFeatures, `RecentExpensesView`)

The row's primary text
([RecentExpensesView.swift:346](../../../Sources/GoldengoFeatures/Recent/RecentExpensesView.swift))
becomes `r.displayTitle`; the secondary (`categoryName ?? "Other"`, line 352) is unchanged. The Undo
toast (lines 163-168) uses `snapshot.displayTitle` for consistency. Requires §1 (snapshot carries the
note).

## Data flow

```
Quick Add: model.note → logManual(note:) → ExpenseRecord.note (trimmed, ""→nil)
Edit:      EditExpenseView note field → model.update(note:) → updateExpense(note:) → ExpenseRecord.note
Read:      ExpenseRecord.note → makeSnapshot → ExpenseSnapshot.note → displayTitle
           → Recent row primary text + Undo toast (note ?? merchant ?? category ?? "Expense")
merchantName: unchanged everywhere (edit-only; still drives subscription detection)
```

## Tests

Pure/logic tested first (failing → green), in `GoldengoDataTests` with an in-memory store; encode the
*why*, not the shape:

- **Note round-trips add → snapshot.** `logManual(... note: "lunch with Ana")`, fetch, assert the
  snapshot's `note == "lunch with Ana"`. *Why: the Recent row and Edit can only show what was bought
  if the note survives to the snapshot.*
- **Whitespace → `nil` on add.** `logManual(... note: "   ")` stores `nil`. *Why: the row must fall
  back to merchant/category, never render a blank line.*
- **Edit sets and clears.** `updateExpense(... note: "x")` sets it; `updateExpense(... note: "  ")`
  clears to `nil`. *Why: editing must be able to remove a note, not just change it.*
- **`displayTitle` precedence.** note-only → note; merchant-only (no note) → merchant; category-only →
  category; none → "Expense"; note present with merchant present → note wins. *Why: the list leads
  with the most specific label the user gave.*

View plumbing (Quick Add note row + keyboard dismissal, Edit field, Recent row text) is verified by
build + simulator logs/screenshot + the device tap-test, not unit tests — per the project convention
that SwiftUI view wiring is runtime-verified.

## Runtime verification

Build for the simulator with seeded data; add an expense with a note via the Quick Add row and confirm
it appears as the Recent row's primary text (screenshot); confirm the keyboard raises over the keypad
and Return returns to the keypad + Add button without covering it permanently. Capture os_log
(`--info --debug`) for AttributeGraph cycles / "modifying state" / hangs while focusing/dismissing the
note field. Second-Opus review over the diff; fix findings. Device install for the user to tap-test the
note entry, the keyboard flow, and the Edit note field (gestures the sim can't drive).

## Out of scope

- No widget change (the widget shows the today **total**, not per-expense descriptions).
- No SwiftData migration (the `note` column already exists).
- No `project.rb` change (all edits are in existing package files; any new test file lives inside the
  package). New `note:` parameters default to `nil` so other `logManual`/`updateExpense` callers are
  untouched.
- Surfacing/editing `merchantName` in Quick Add — deliberately kept edit-only.
