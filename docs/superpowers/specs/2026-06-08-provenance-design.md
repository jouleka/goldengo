# GOL-81 — Provenance (money carries where it came from)

**Ticket:** [GOL-81](https://mysigner.youtrack.cloud/issue/GOL-81).
**Status:** design approved; pending spec review.
**Date:** 2026-06-08.
**Origin:** flagship pick from the post-GOL-80 ultracode ideation (survived adversarial novelty + feasibility vetting).
**Builds on:** existing `TransactionKind.income`, statement-import income tagging, `CurrencyConverter`/`RateTable` (on-device FX), `IngestionStore` capture path, `RecentExpensesView` (already styles income rows).

## Goal

Money carries its **origin**. The user logs named inflows — "€200 from Sister", "5000 cash withdrawal", "Freelance 30000" — and each becomes a distinctly-colored **Source**. As they spend, a deterministic FIFO allocator drains the oldest source first; the user watches each source's balance shrink and sees "funded by Sister" on a spend. This restores the *felt cost* that cards/totals delete, routed through meaning instead of a scolding budget — and it is something **bank-sync incumbents structurally cannot build** (they only see card rails; they have no remittance/cash-withdrawal source object or per-expense FIFO drawdown).

## Decision record (brainstorm)

- **Attribution = automatic FIFO** (chosen over per-expense tagging and over a hybrid override). The user names income when it arrives; every expense draws from the **oldest non-depleted source first**, computed — zero extra taps per spend (fits the minimalist/low-tap ethos). Per-expense override is an explicit non-goal for v1.
- **Inflows = manual only** (chosen over folding in imported statement income, and over cash-only). The user logs named inflows; a cash withdrawal is just a named inflow (no separate `transfer` logic). Imported statement income stays as plain income for now.
- **Surface = a dedicated Sources screen + "funded by" inline** (chosen over inline-only and over an animated home hero). The animated hero ("The Weight" draining a source) is a deliberate fast-follow layered on top once the model is proven.
- **Allocation is computed, never stored.** Recomputed from the ordered ledger on every read, so edits/deletes just re-run FIFO — nothing to desync. `Decimal` math stays in plain Swift, never in a `#Predicate` (the SwiftData segfault rule).
- **`AccountRecord` is NOT reused.** It's a dormant payment-account model (cash/card), never instantiated anywhere; Provenance's "source" (income origin) is a distinct concept, so a new model is cleaner than bending the account one.

## Components

### 1. `SourceRecord` — `Sources/GoldengoData/Models/SourceRecord.swift`
A named money origin.
```
@Model final class SourceRecord {
    var id: String                    // stable UUID string — the allocator's sourceID (rename-safe)
    var name: String                  // "Sister", "Freelance", "Friday cash"
    var currencyCode: String          // the source's native currency, e.g. "EUR", "ALL"
    var colorIndex: Int               // palette slot for the distinct color
    var createdAt: Date
    var isArchived: Bool              // soft-delete tombstone (CloudKit-friendly), matches ExpenseRecord
    @Relationship(deleteRule: .nullify, inverse: \ExpenseRecord.provenanceSource)
    var incomes: [ExpenseRecord]?     // CloudKit REQUIRES an inverse (cf. AccountRecord)
}
```
`name` is unique via case-insensitive find-or-create, but the allocator keys on the stable `id` (not the name) so a future rename can't break attribution. The store maps `SourceRecord.id` → `Inflow.sourceID` and `Allocation.remainingBySource[id]` back to source metadata.

### 2. `ExpenseRecord.provenanceSource: SourceRecord?` (new optional relationship)
Set **only on income records** (`kind == .income`) — which named source this inflow belongs to. **Named `provenanceSource`, not `source`,** to avoid colliding with the existing computed `var source: ExpenseSource`. Expenses (`.expense`) never store a source; their funding is computed. Register `SourceRecord` in `ModelContainer.goldengoSchema`. Migration is additive (new model + one optional relationship) → lightweight/automatic under SwiftData+CloudKit.

### 3. `ProvenanceAllocator` — `Sources/GoldengoCore/ProvenanceAllocator.swift` (pure, the tested core)
No SwiftData, no UIKit. Deterministic value-in/value-out.
```
struct Inflow  { let id: String; let sourceID: String; let amount: Decimal; let currency: CurrencyCode; let date: Date }
struct Outflow { let id: String; let amount: Decimal; let currency: CurrencyCode; let date: Date }
struct FundingSegment { let sourceID: String; let amount: Decimal }   // amount in the SOURCE's currency
struct Allocation {
    let remainingBySource: [String: Decimal]      // source currency, never negative
    let fundingByOutflow:  [String: [FundingSegment]]
    let totalUnaccounted:  Decimal                // in a chosen display currency
}
enum ProvenanceAllocator {
    static func allocate(inflows: [Inflow], outflows: [Outflow], rates: RateTable,
                         displayCurrency: CurrencyCode) -> Allocation
}
```
Algorithm: sort inflow lots and outflows by `date` ascending (stable). Maintain each lot's remaining (in its own currency). For each outflow in date order, draw from the **oldest non-depleted lot first**; convert the outflow's still-unfunded amount into that lot's currency via `CurrencyConverter(table: rates)`; take `min(needed, lotRemaining)`; record a `FundingSegment` and decrement the lot. An outflow can span multiple lots. Any portion that no lot can cover (spend before/beyond all inflows) accrues to `totalUnaccounted` (converted to `displayCurrency`). `remainingBySource` = each source's lots summed.

### 4. `IngestionStore` additions — `Sources/GoldengoData`
- `logIncome(amount:currency:sourceName:date: Date = .now)` — trim + find-or-create `SourceRecord` by case-insensitive name (mirrors `findOrCreateCategory`), insert an `.income` `ExpenseRecord` linked via `provenanceSource`, save, refresh shared totals.
- `provenanceSnapshot(displayCurrency:)` — fetch non-archived income (with `provenanceSource`) + non-archived expenses, build `Inflow`/`Outflow` arrays, run `ProvenanceAllocator` with cached rates (`ExchangeRateCache().load() ?? SeedRates.table`), return per-source balances (+ source metadata) and the funding map. Used by the Sources screen and the "funded by" labels.
- `findOrCreateSource(named:currency:)`, `sources()` (non-archived).

### 5. UI — `Sources/GoldengoFeatures/Provenance/`
- **`SourcesView` + `SourcesModel`** (a new 4th tab). Each source: name, color, **remaining** in native currency + preferred-currency equivalent, and a draining progress bar (`remaining / totalInflow`). An **"Unaccounted"** row (muted/warning) when `totalUnaccounted > 0`, with a gentle "log where this came from" nudge. A **"+ Income"** button → income-entry sheet.
- **Income entry sheet** — amount (reuse the QuickAdd keypad), currency picker (reuse `CurrencyPickerView`), a source-name field with suggestions from existing sources, date (default today). Save → `logIncome`. Keyboard dismissal via tap-outside/Return (no Done toolbar), per conventions.
- **"funded by …" line** on expense rows in `RecentExpensesView` (computed from the snapshot; income rows are already styled there). Hidden when funding is fully Unaccounted (don't show a confusing label).
- Built with the frontend-design skill at implementation time; minimalist, low-tap.

## Data flow
```
Add income ("€200 from Sister")  → logIncome → SourceRecord(find-or-create) + .income ExpenseRecord(provenanceSource)
Spend (existing logManual/scan/import) → .expense ExpenseRecord (no source stored)
SourcesView / Recent  → provenanceSnapshot(displayCurrency: preferred)
    → ProvenanceAllocator.allocate(inflows, outflows, rates)  [pure, FIFO oldest-first, currency-converting]
    → per-source remaining (draining bars) + per-expense "funded by" + Unaccounted total
Edit/delete any income or expense → next snapshot just re-runs the allocator (nothing stored to desync)
```

## Error handling / edge cases
- Empty/whitespace source name → rejected at entry; duplicate names collapse via case-insensitive find-or-create (trimmed).
- A fully-drained source still shows (0 remaining) until archived.
- Deleting/archiving a source nullifies its income links (`.nullify`); those inflows become Unaccounted on the next recompute (no orphan crash).
- Expense dated before any inflow → Unaccounted (FIFO by date; income added later does NOT retroactively fund an earlier expense).
- Missing FX rate for a source currency → `CurrencyConverter` falls back to the seeded/cached table (same behavior as the dashboard total today); never crash.

## Tests
- **`ProvenanceAllocatorTests` (GoldengoCoreTests) — the bulk:** FIFO oldest-first; one outflow spanning two lots (correct segments); cross-currency (a EUR source funds an ALL expense at a known `RateTable` rate); overspend → `totalUnaccounted`; expense dated before any inflow → Unaccounted (no retroactive funding); multi-source `remainingBySource` correct; remaining never negative. *Why each matters:* a wrong allocation silently lies about whose money funded what — the emotional core — so these must fail if FIFO/conversion regresses (Rule 9).
- **`IngestionStore` tests (GoldengoDataTests):** `logIncome` creates a source + linked `.income` record; `findOrCreateSource` is case-insensitive; `provenanceSnapshot` returns correct balances + funding against an in-memory store.
- **UI** (`SourcesModel`): snapshot → view-state mapping (balances, bars, Unaccounted) testable on macOS with an in-memory store; `SourcesView` rendering verified on device.

## Out of scope (explicit, v1)
- Per-expense source override / re-assignment (pure FIFO only).
- Folding imported statement income into sources.
- Animated home-screen hero ("The Weight" draining a source) — the planned fast-follow.
- Per-source budgets/targets, source archiving UI beyond basic, source merging.
- Transfers (`.transfer` kind) between sources/accounts.
