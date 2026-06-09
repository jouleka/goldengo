# Home load performance — single-fetch consolidation + fingerprint-keyed FIFO cache

**Ticket:** [GOL-86](https://mysigner.youtrack.cloud/issue/GOL-86).
**Status:** design approved; pending spec review.
**Date:** 2026-06-09.
**Origin:** the deferred performance follow-up flagged in **GOL-81 (Provenance)** and **GOL-82 (Rhythm Ledger)** — "Home `load()` runs multiple independent full-expense scans + recomputes the full FIFO ledger every load."
**Builds on:** `IngestionStore` (`@ModelActor`), `RecentExpensesModel`, `RecentExpensesReading`, `ProvenanceAllocator`, `RhythmDetector`, `IngestionStore+Provenance`, `IngestionStore+Dashboard`, `IngestionStore+Rhythm`.

## Goal

Cut the wasteful **constant factor** of a Home dashboard reload without changing any user-visible behavior. Today one `RecentExpensesModel.load()` triggers **5 distinct `ExpenseRecord` fetches** (2 of them full unbounded scans), an **N+1 `MerchantRecord` fetch** (one per ghost), **4 actor round-trips**, and **1 full FIFO allocation** (`O(outflows×inflows)`) — much of it redundant. Collapse the reads into **one fetch + in-memory derivation**, and **memoize the FIFO allocation** so an unchanged reload doesn't re-run it.

**Honest bound:** the load stays **O(expenses)** — rhythm detection and FIFO genuinely need full history, so this is not a sub-linear change. It removes redundant work, not the linear floor.

## Verified current cost (from the exploration workflow)

Per `RecentExpensesModel.load()` (`RecentExpensesModel.swift:23-37`):
- `recentExpenses(limit:50)` → `fundingLabels` → `compute()` (`IngestionStore+Provenance.swift:83-105`): **full unbounded `ExpenseRecord` scan #1 + full FIFO** just to label the 50 visible rows; also a full `SourceRecord` scan.
- `recentExpenses`'s own top-50 fetch (`IngestionStore.swift:128-132`) — bounded subset.
- `todayTotal` today-scoped fetch (`IngestionStore.swift:144-147`) — bounded subset.
- `dashboardSummary` month-scoped fetch + confirmed-subscriptions fetch (`IngestionStore+Dashboard.swift:41-44, 60-62`) — bounded subset.
- `rhythmGhosts` (`IngestionStore+Rhythm.swift:19-20`): **full unbounded `ExpenseRecord` scan #2** + per-ghost `MerchantRecord` fetch (`Rhythm.swift:53-57`, N+1).
- No `relationshipKeyPathsForPrefetching` anywhere → lazy `category`/`subscription` faults during `makeSnapshot` and the dashboard loop.
- **1** full FIFO on Home (the second FIFO, via `provenanceSnapshot`, is the **Sources tab only** — not the Home path).

The three bounded fetches (top-50, today, month) are strict **subsets** of the two unbounded scans, so today's rows are read up to 4× per load.

## Architecture

Two changes, both inside `GoldengoData`; the pure cores (`ProvenanceAllocator`, `RhythmDetector`, `CurrencyConverter`) are **untouched**.

### 1. `homeData(...)` — one fetch, in-memory derivation

A new actor method on `IngestionStore` (and on the `RecentExpensesReading` protocol):

```swift
public struct HomeData: Sendable {
    public let rows: [ExpenseSnapshot]      // recent 50, with fundedBy labels
    public let todayTotal: Decimal
    public let summary: DashboardSummary
    public let ghosts: [RhythmGhost]
}

func homeData(in displayCurrency: CurrencyCode, rates: RateTable,
              now: Date, topCategoryLimit: Int) async throws -> HomeData
```

Implementation:
- **One** `ExpenseRecord` fetch: `FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.isArchived == false }, sortBy: [.init(\.date, order: .reverse)])` with `relationshipKeyPathsForPrefetching = [\.category, \.subscription, \.provenanceSource]`. No `fetchLimit` (full history is needed for FIFO + rhythm), no Decimal in the predicate. This is the same row set `compute()` and `recentExpenses` each fetch today — we now fetch it once and reuse it for all derivations.
- Net fetch count per `homeData`: **1 big** `ExpenseRecord` scan (shared) **+ 3 small**: `SourceRecord` (for the allocator inflows + funding-label names), confirmed `SubscriptionRecord` (dashboard), and **one batched** `MerchantRecord` fetch (ghost categories). Down from today's ~8 fetches (2 big unbounded `ExpenseRecord` scans + N+1 merchant) across 4 round-trips.
- To make "fetch once" real, `compute()` is split into (a) a pure **materialize-and-allocate** step that takes already-fetched `[ExpenseRecord]` + `[SourceRecord]`, and (b) the existing **fetch-then-materialize-and-allocate** entry the granular `fundingLabels`/`provenanceSnapshot` use. `homeData` calls (a) with its single expense fetch + one source fetch; the granular methods keep calling (b). Both funnel into the same fingerprint-keyed allocate (§2).
- From that single in-memory array, derive each result **using exactly today's logic**, just sourced from the shared array instead of re-fetching:
  - **rows**: first 50 (already date-desc), `makeSnapshot`; `fundedBy` for expense-kind rows from the funding-label map (see §2). Funding labels use the **SharedSummary preferred currency** (as `fundingLabels` does today — preserved exactly).
  - **todayTotal**: in-memory filter `kind==expense && date>=startOfDay(now)`, map→`Money`, `CurrencyConverter(...).sum(to: displayCurrency)`.
  - **summary**: in-memory filter `kind==expense && date>=monthStart(now)`, reuse the existing dashboard reduction (month total, byCategory, `usedConversion`/`ratesAsOf`, topCategoryLimit). The confirmed-subscriptions fetch stays a separate (small, distinct-entity) fetch.
  - **ghosts**: in-memory filter `kind==expense`, `abs($0.amount)`, build `TransactionOccurrence`s, `RhythmDetector.detect`, then the **local-day** suppression set (preserved — do **not** align with the detector's UTC grouping). Ghost category lookups batched into **one** `MerchantRecord` fetch via a string `contains` predicate over the surfaced ghosts' normalized names (no Decimal).
- **Error semantics preserved:** ghost derivation is wrapped `try?` *inside* `homeData` so a rhythm failure yields `[]` and never fails the load; the recent/today/month derivations propagate errors so the model keeps prior rows and sets `loadFailed` (unchanged behavior).
- `RecentExpensesModel.load()` calls **only** `homeData(...)` (1 round-trip). `delete`/`restore`/`update`/`confirm` still call their existing methods then `await load()`.

The existing granular methods (`recentExpenses`, `todayTotal`, `dashboardSummary`, `rhythmGhosts`) **stay** on `IngestionStore` (still used by `EveningModel`, `SourcesModel`, and the parity tests) and on the protocol; they are simply no longer on the Home hot path.

### 2. Fingerprint-keyed FIFO allocation cache

The allocation depends only on the provenance-relevant inputs + display currency + rate table. Cache it keyed on a **content fingerprint** so it can never serve stale data.

Inside `IngestionStore` (actor-isolated; stores a pure Sendable `Allocation`, never `@Model`s):

```swift
private struct LedgerFingerprint: Equatable {
    let currencyCode: String
    let ratesAsOf: Date?
    let inflowKeys: [String]    // "<id>|<epochDay-or-time>|<amount>|<currency>|<sourceID>"
    let outflowKeys: [String]   // "<id>|<time>|<amount>|<currency>"
}
private var cachedAllocation: (fingerprint: LedgerFingerprint, allocation: Allocation)?
private(set) var allocationComputeCount = 0   // test observability only
```

`compute(rates:displayCurrency:)` is refactored so the `ProvenanceAllocator.allocate(...)` step goes through a memoizing helper: build the fingerprint from the materialized `inflows`/`outflows` + `displayCurrency` + `rates.asOf`; if it equals `cachedAllocation?.fingerprint`, reuse the stored `Allocation`; otherwise run the allocator, store `(fingerprint, allocation)`, and bump `allocationComputeCount`. `compute()` still produces the source-name/meta mapping each call (cheap, from the in-hand sources).

**Why this is stale-proof:** the fingerprint is rebuilt from *current* data on every call. Any change — a local edit/delete/add-income, a date move that reorders the FIFO, a display-currency change, a rate-table refresh, **or a CloudKit remote merge** — changes the fingerprint and forces a recompute. The cache is pure memoization; the computed-not-stored invariant is preserved. Home (`fundingLabels` via `homeData`) and the Sources tab (`provenanceSnapshot`) share the cache.

> A naive cache invalidated only on local writes would **regress** multi-device users: today (no cache) a remote sync is reflected on the next `load()` because everything recomputes. The fingerprint approach keeps that correctness automatically.

## Data flow

```
RecentExpensesModel.load(currency)
  → reader.homeData(in: currency, rates, now, topCategoryLimit: 4)
      → ONE fetch: all non-archived ExpenseRecord (date desc, prefetch category/subscription/provenanceSource)
      → rows(50) + fundingLabels(preferred ccy)   ┐
      → todayTotal(currency)                        │ all derived from the one array
      → dashboardSummary(currency) [+ subs fetch]   │
      → ghosts (try?) [+ 1 batched merchant fetch]  ┘
      → fundingLabels/provenanceSnapshot → compute() → allocate() via fingerprint cache
  → assign rows/todayTotalText/summary/ghosts; loadFailed=false
mutation (delete/restore/update/confirm/addIncome) → fingerprint changes next load → cache miss → recompute
```

## Error handling / edge cases

- **Partial failure:** recent/today/month errors throw → model keeps prior rows + `loadFailed=true` (unchanged); ghost errors are swallowed (`try?` → `[]`) so they never blank the dashboard (unchanged).
- **CloudKit remote change:** reflected automatically via the fingerprint (no stale funding labels/balances).
- **Currency / rate change:** fingerprint includes `currencyCode` + `ratesAsOf` → recompute.
- **Date-only edit:** `updateExpense` changing only a date reorders FIFO; the outflow key includes the date → fingerprint changes → recompute.
- **Empty ledger / first launch:** zero inflows+outflows → allocator returns empty; fingerprint stable; no crash.
- **macOS / tests:** no platform-specific APIs added; package still builds for macOS.

## Invariants preserved (must not regress)

1. **No Decimal in any `#Predicate`** (SIGSEGV) — all amount/merchant filtering stays in memory; the new batched merchant fetch uses a String `contains` only.
2. **Only Sendable snapshots cross the `@ModelActor` boundary** — `HomeData` is a Sendable value; the cache stores the pure `Allocation`, never fetched `@Model`s.
3. **Computed-not-stored** provenance/rhythm — no allocation persisted; the cache is fingerprint-memoization, always derived from current data.
4. **Local-day ghost suppression** kept distinct from the detector's UTC-day grouping (do not "align").
5. **Rhythm needs full history** — the shared fetch is unbounded (never the top-50 slice).
6. **Currency duality** — funding labels use SharedSummary preferred currency; today/month totals use the model's `currency` arg (both preserved; not unified).
7. **`logIncome` does not refresh the widget total**, expense paths do — unchanged.
8. **`RecentExpensesReading` + `FailingReader` change in lockstep**; per-call error granularity preserved (rhythm best-effort).
9. **kind/archived/month/day filters + per-row currency conversion + `usedConversion`/`ratesAsOf`** bookkeeping identical to today.

## Tests

- **Parity (`GoldengoDataTests`):** over a seeded store (mixed currencies, incomes+expenses, a daily-pattern merchant, today + this-month + older rows), assert `homeData(...)` returns the **same** `rows` (incl. `fundedBy`), `todayTotal`, `summary` (monthTotal, byCategory, ratesAsOf), and `ghosts` as the four existing granular methods. This is the behavior-preservation gate.
- **Cache hit:** two `homeData`/`fundingLabels` calls with no mutation between them → `allocationComputeCount` increments **once**, not twice.
- **Cache invalidation by content:** after each of `logIncome`, `logManual`, `deleteExpense`, `restoreExpense`, `updateExpense (amount)`, `updateExpense (date only)`, and a display-currency change → the next call **recomputes** (`allocationComputeCount` increments) and the funding labels / source balances reflect the change.
- **No-Decimal-in-Predicate:** full `swift test` (the suite SIGSEGVs if violated).
- **Error semantics (`GoldengoFeaturesTests`):** `FailingReader.homeData` throws → `load()` sets `loadFailed`, prior rows preserved (mirror the existing `test_load_failure`).

## Out of scope (explicit, v1)

- Incremental/streaming FIFO (recompute-only-the-delta) — still a full allocation on any change; only the *unchanged-reload* case is memoized.
- Caching the rhythm-detection result or the dashboard reduction (cheaper than FIFO; left linear).
- Pagination of Recent beyond the existing 50-row cap.
- Unifying the funding-label vs totals currency duality (deliberately preserved).
- Any schema/model change (this is pure read-path refactoring).
