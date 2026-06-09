# GOL-89 — Source pinning (choose which income funds an expense) + funded-by chip polish

**Ticket:** [GOL-89](https://mysigner.youtrack.cloud/issue/GOL-89).
**Status:** building (user delegated end-to-end: "fix all the relevant issues and come back to me once done").
**Date:** 2026-06-10.
**Origin:** on-device feedback on GOL-81 Provenance: can't choose which income funds an expense, can't edit it, and the "funded by" label looks rough.

## Goal

Let the user say "this expense came from *that* money" — at edit time — while keeping the automatic FIFO as the no-effort default. And make the funded-by row label visually quiet and color-matched to the Sources tab.

## Design decisions

1. **A pin, not a reallocation UI.** Each expense gets an optional `fundedBySourceID` ("pin"). Unpinned expenses keep automatic FIFO. Editing is enough (QuickAdd stays low-tap; you can pin after logging) — deliberate v1 scope.
2. **Storage: a new additive optional attribute** `ExpenseRecord.fundedBySourceID: String?` — NOT the existing `provenanceSource` relationship, which is income-only and whose inverse (`SourceRecord.incomes`) feeds `provenanceSnapshot`'s `totalInflow`; reusing it would corrupt source balances. A plain string ID is also rename-safe (`SourceRecord.id` is a stable UUID). Additive optional → lightweight migration, CloudKit-safe (same class as GOL-81's own migration).
3. **Allocator semantics (pure core, tested):** `Outflow` gains `pinnedSourceID: String?` (defaulted — existing call sites unchanged). `allocate` runs two passes:
   - **Pass 1 — pinned outflows** (date,id order): draw **only** from the pinned source's lots, **ignoring the `lot.date <= out.date` rule** (the user explicitly stated the origin; logging order shouldn't fight them). Shortfall → `unaccounted` — **no silent fallback** to other sources (the pin is a statement of fact; if the pool lacks the money, surfacing the gap is honest).
   - **Pass 2 — unpinned outflows**: the existing FIFO over the remaining lots, date rule intact.
   - Pins therefore **reserve** their money before automatic allocation — deterministic and explainable.
4. **Cache:** the fingerprint's outflow keys append the pin, so editing a pin invalidates the cached allocation. Computed-not-stored is preserved — the pin is *data*; funding labels/balances still re-derive every load.
5. **Edit UI:** `EditExpenseView` gains a **"Paid from"** section (expense rows only): a horizontal chip row — **Automatic** + one chip per named source (palette-color dot + name), mirroring the category-chip pattern in the same sheet. Preselected from the row's pin. Saved through `updateExpense`, whose signature gains a non-defaulted `fundedBySourceID: String?` (the final value, always applied — the sheet knows the full state; no tri-state).
6. **Source options with zero extra fetch:** `HomeData` gains `sources: [FundingSourceOption]` (`{id, name, colorIndex}`, Sendable) — built from the source fetch `homeData` already does. `RecentExpensesModel` exposes them to the edit sheet.
7. **Chip polish:** replace `Label("funded by …", systemImage: "arrow.down.left.circle")` with a quiet capsule chip: a 6pt dot in the source's palette color + "from Sister", caption2 on `goldengoField`. The palette moves to `GoldengoTheme.sourceColor(_:)` (design system) so the chip and the Sources tab bars share colors exactly; `SourcesModel` delegates to it. Funding labels gain a `colorIndex` (first funding segment's source) carried on `ExpenseSnapshot.fundedByColorIndex`.

## Touched surface

- `GoldengoCore/ProvenanceAllocator.swift` — `Outflow.pinnedSourceID`, two-pass allocate.
- `GoldengoData/Models/ExpenseRecord.swift` — `fundedBySourceID: String?`.
- `GoldengoData/IngestionStore+Provenance.swift` — `buildAllocatorInputs` passes pins; `fundingLabelMap` returns label+colorIndex; `FundingSourceOption`.
- `GoldengoData/IngestionStore.swift` — fingerprint outflow key includes pin; `makeSnapshot` carries pin; `ExpenseSnapshot` + `fundedBySourceID`/`fundedByColorIndex`; `recentExpenses` sets both.
- `GoldengoData/IngestionStore+HomeData.swift` — `HomeData.sources`; sets both label fields.
- `GoldengoData/IngestionStore+Editing.swift` — `updateExpense(... fundedBySourceID:)`.
- `GoldengoData/RecentExpensesReading.swift` — updated `updateExpense` signature.
- `GoldengoDesignSystem/GoldengoTheme.swift` — `sourceColor(_:)` palette.
- `GoldengoFeatures` — `EditExpenseView` Paid-from section; `RecentExpensesView` chip + wiring; `RecentExpensesModel.update` param + `fundingSources`; `SourcesModel` palette delegation.
- Tests: allocator pin semantics; store pin set/clear + labels + cache invalidation; mocks in lockstep.

## Invariants preserved

No Decimal/array-`.contains` in any `#Predicate`; only Sendable values cross the actor; computed-not-stored (pin is data, allocation still derived); rhythm/dashboard untouched; existing unpinned FIFO behavior byte-identical (pass 2 is the old loop).

## Out of scope (v1, deliberate)

- Choosing a source at QuickAdd time (Add stays low-tap; pin after via Edit).
- Splitting one expense across chosen sources (pins are whole-expense).
- Re-pinning income rows (pin is expense-only).
