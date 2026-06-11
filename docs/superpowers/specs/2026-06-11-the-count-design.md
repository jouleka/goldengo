# The Count (cycle 1) — the cash wallet as a place that can tell the truth

**Status:** design approved; pending spec review.
**Date:** 2026-06-11.
**Origin:** ideation round 2 anchor concept (`docs/superpowers/ideation/2026-06-11-round-2.md`) — merged from five cash-reconciliation lenses + the Wallet Truth seed; survived prior-art and usefulness assassins.
**Builds on:** statement import (`GoldengoImport`, `StatementProfile`, `RaiffeisenAlbaniaParser`), the reserved-but-unused `TransactionKind.transfer`, `logManual`/dedupe-key prefixes, the Sources tab, the ghost-row pattern, the drop haptic.

## Goal

Your physical wallet becomes a first-class place. ATM withdrawals seen by statement import feed it; hand-logged spends drain it; whenever you feel like it — never prompted, never scheduled — you count the notes actually in your hand on a denomination grid, and the gap between counted and expected becomes one quiet, one-tap "street money" entry. A ten-second count repairs a week of missed logs. The standing line: **cash moves; you don't owe it a story.**

## Decision record (brainstorm)

- **Wallet = pure derived ledger, NOT a `SourceRecord`** (approach A over the panel's FIFO-tranche sketch): Provenance answers "which income paid for this"; the wallet answers "what's in my pocket" — orthogonal questions, no coupling. Cycle 2's half-life can derive tranche math from the same transfer rows later without touching `SourceRecord`.
- **Manual = cash by default, NO override control in v1.** Hand-typed/quick-logged expenses and manual income are cash; imported/Apple Pay rows are card. A misclassified hand-logged card purchase simply becomes drift, and the next count absorbs it — **the count self-corrects all marking errors.** (User-chosen over an explicit pin and over a payment-method field.)
- **ATM rows import as `.transfer`** — already a `TransactionKind` case, used nowhere, and every total/dashboard filters on `expense`, so the current withdrawal-plus-spends double-count ends naturally. **Future imports only** (user-chosen): history stays as verified; accuracy starts from the first count anyway.
- **The count is truth.** Saving a count always resets the baseline. Negative drift offers a ghost (accept → recorded expense; decline → the gap goes unrecorded — user's call, calm either way). Positive drift resets with a gentle line and fabricates nothing.
- **Drift entries are excluded from wallet math by IDENTITY, not by date** — `drift:` dedupe-key prefix (the GOL-92 lesson: keying behavior on mutable fields like dates corrupts ledgers when users edit; prefixes are forever).
- **ALL only in v1** (EUR/USD wallets are cycle 2+). Bank of Albania denominations: notes 200/500/1000/2000/5000/10000 lekë, coins 1/5/10/20/50/100 lekë (10,000-lek note verified — issued 2021).
- **Unscheduled, unprompted.** No reminders, no badge, no red. The Count is opened, never pushed.

## Components

### 1. `CashLedger` — pure (GoldengoCore)

```swift
public enum CashLedger {
    /// Expected wallet contents: the latest count's total, plus cash inflows after it
    /// (ATM transfers + manual income), minus cash outflows after it (manual expenses,
    /// drift entries excluded by identity).
    public static func expected(baseline: (date: Date, total: Decimal),
                                flows: [Flow]) -> Decimal
    public struct Flow: Sendable { date: Date; amount: Decimal; direction: in/out }
    /// counted − expected. Negative = cash slipped by unlogged.
    public static func drift(counted: Decimal, expected: Decimal) -> Decimal
}
```
The store maps records → `Flow`s (it owns the manual/transfer/prefix selection rules); the ledger stays arithmetic, fully unit-tested.

### 2. `Denominations` — pure (GoldengoCore)

```swift
public enum Denominations {
    public static let lekNotes: [Int]  = [10000, 5000, 2000, 1000, 500, 200]
    public static let lekCoins: [Int]  = [100, 50, 20, 10, 5, 1]
}
public struct DenominationTally: Codable, Equatable, Sendable {
    public var counts: [Int: Int]      // denomination → count
    public var total: Decimal          // computed
}
```

### 3. `WalletCount` — @Model (GoldengoData)

`date: Date`, `tallyData: Data` (JSON-encoded `DenominationTally`; CloudKit-safe blob), `total: Decimal` (denormalized for queries — never compared inside a `#Predicate`), `isArchived` tombstone. Store API (`IngestionStore+Wallet.swift`):
- `recordWalletCount(_ tally: DenominationTally, at: Date) -> WalletCountOutcome` — saves the count and returns a Sendable outcome `{ countedTotal, expected, drift }` computed against the prior baseline (nil expected/drift on the first-ever count).
- `walletSnapshot(now:) -> WalletSnapshot?` — `{ baselineDate, countedTotal, expectedNow }` for the Sources-tab card; nil before the first count.
- `logDrift(amount: Decimal, at: Date)` — `logEntry` with keyPrefix `"drift"`, source `.manual`, category "Unaccounted", note "street money". Ordinary visible, editable, deletable expense.
- Cash-flow selection (in-memory after fetch, Decimals never in `#Predicate`): inflows = `kind == .transfer` rows + `kind == .income && source == .manual`; outflows = `kind == .expense && source == .manual && !dedupeKey.hasPrefix("drift:")`; all `date > baselineDate`, non-archived.

### 4. Import tagging (GoldengoImport)

`StatementProfile` gains `atmKeywords: [String]` (raiffeisenAlbania: `["terheqje", "tërheqje", "atm", "bankomat", "cash withdrawal"]`, matched case-insensitively against the row description). `RaiffeisenAlbaniaParser`/`StatementRowMapper`: a debit row matching an ATM keyword maps to `kind: .transfer` instead of `.expense`. Everything downstream (ingest, dedupe) already carries `kind` through; totals exclude transfers by their existing `expense` filters.

### 5. UI (GoldengoFeatures)

- **Wallet card** on the Sources tab, above the source list: "In your wallet · ~12,400 ALL" (expectedNow), the last-count date as a caption, and a **Count** button. Before the first count: "Count your wallet to begin." No card states are red; drift is weather, not failure.
- **Count sheet**: a denomination grid — one oversized row per note/coin (note value + a stepper/tap-to-increment with the count), running total live at the top, **Save** (drop haptic). Keyboard never appears (steppers only).
- **Drift moment** (inside the sheet flow, post-save): negative drift → the ghost line "X lekë slipped by since ⟨baseline date⟩ — keep it as street money?" with one **Keep** button and a quiet "Let it go" dismissal. Positive drift → "Your wallet is X ahead of the books — baseline updated." Either way the baseline is already reset.
- **Transfer rows in Recent**: neutral quiet styling, title "ATM → wallet", no income-green/expense color.

## Data flow

```
statement import → ATM row → kind .transfer (excluded from spend totals; wallet inflow)
manual add (expense) → cash outflow            manual add-income → cash inflow
Sources tab → wallet card: expected = baseline.total + inflows − outflows (since baseline)
Count → save tally → outcome { counted, expected, drift } → baseline := this count
  drift < 0 → ghost → Keep → drift: entry (visible expense; excluded from wallet math forever)
  drift ≥ 0 → gentle line, nothing fabricated
```

## Error handling / edge cases

- First-ever count: no expected, no drift — baseline seeded.
- Counts are editable history? No — v1 counts are append-only (a wrong count is fixed by counting again; tombstone delete supported but no edit UI).
- Drift entry later deleted by the user → it simply stops existing as an expense; wallet math never depended on it (identity-excluded).
- Backdated manual expenses (date set before the baseline) → excluded from expected (they belong to a pre-count era the count already absorbed). Documented behavior.
- Clock skew / count "in the future": baseline date = save time; flows use `>` strictly.
- ATM keyword false positive (a merchant named "Atmosfera") → keywords match word-prefix tokens, and a mis-tagged row is a visible transfer row the user can edit; worst case = a spend missing from totals until corrected, never money invented. Keyword list is profile-scoped and tuned against real statements at implementation.
- CloudKit two-device counts: latest-date count wins as baseline (deterministic ordering by date, then a stable tiebreak).

## Tests

- **`CashLedgerTests` (Core):** expected with no flows; inflow/outflow mixes; strict date boundary; drift sign conventions.
- **`DenominationsTests` (Core):** tally totals; Codable round-trip; the lek tables.
- **Import (GoldengoImportTests):** ATM-keyword row → `.transfer`; non-ATM debit unchanged; keyword case-insensitivity.
- **Store (GoldengoDataTests):** first count seeds baseline; outcome drift math against seeded flows; drift entry exclusion (log drift → expected unchanged); manual-income inflow; imported expense NOT an outflow; transfer NOT in spend totals (dashboard regression).
- **Count sheet / card / ghost moment:** device-verified.

## Out of scope (cycle 2 ticket, explicit)

- Withdrawal half-life + next-ATM-run prediction; fog-in-notes rendering; Home card/widget surface; EUR/USD wallets; positive-drift income ghosts; Kusur Keypad (rides this substrate later); count editing; retro-tagging historical ATM rows.

## Revision after adversarial review (same day)

Three review lenses confirmed 7 distinct defects (13 raw findings, heavily cross-confirmed); all fixed before merge:

- **Sibling-kind dedupe convergence:** `kind` is part of the composite dedupeKey, so the same ATM row keyed pre-feature as an *expense* and re-imported as a *transfer* (or arriving expense-keyed from a keyword-less CSV when the transfer copy exists) slipped past the exact match and duplicated. `ingest` now probes the opposite-kind composite key for expense↔transfer pairs and converges the pair on **`.transfer`** — re-importing an old statement heals that row's withdrawal double-count in place. (This refines "future imports only": bulk history is still untouched, but re-imported rows converge.)
- **Fee rows are spend, never inflows:** `atmExclusionKeywords` ("komision", "fee", "tarifa", …) veto the withdrawal match before it is attempted — "KOMISION TERHEQJE ATM" stays an expense. Albanian inflected forms ("terheqja", "bankomati", …) added to the positive lists.
- **An empty wallet is countable:** the zero-total guard on Save is gone — a full drain must be reconcilable.
- **Double-tap guards** on Save count and Keep it (synchronous `busy` flag before the first await — unique keys never dedupe).
- **First-count copy** says "Baseline set — your wallet starts here…" (nil drift is not zero drift).

Accepted limitations added: a failed-withdrawal *reversal credit* is not netted against its debit (the transfer inflow stands until the next count's drift absorbs it — rare, self-correcting); a mis-tagged transfer row has no kind-edit UI in v1 (delete the row and hand-log the spend, or recount).
