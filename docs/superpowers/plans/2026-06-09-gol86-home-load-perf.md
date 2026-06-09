# GOL-86 — Home load performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the redundant constant-factor cost of a Home reload — collapse 5 `ExpenseRecord` fetches + N+1 merchant fetches + 4 actor round-trips into one `homeData(...)` (single full fetch → in-memory derivation), and memoize the FIFO allocation with a stale-proof content fingerprint.

**Architecture:** Pure read-path refactor inside `GoldengoData`; the pure cores (`ProvenanceAllocator`, `RhythmDetector`, `CurrencyConverter`) are untouched. A fingerprint-keyed allocation cache lives on the `IngestionStore` actor. A new `homeData(...)` actor method fetches all non-archived `ExpenseRecord` once and derives recent-50/today/month/ghosts from that single array via extracted helpers shared with the existing granular methods.

**Tech Stack:** Swift 6, SwiftData (`@ModelActor`), XCTest. `swift test` runs on macOS → no iOS-only APIs added.

**Spec:** `docs/superpowers/specs/2026-06-09-home-load-perf-design.md`.

**Invariants that must not regress** (verified in the spec): no Decimal in any `#Predicate`; only Sendable snapshots cross the actor boundary (cache stores the pure `Allocation`, never `@Model`s); computed-not-stored provenance (the cache is fingerprint-memoization); local-day ghost suppression distinct from the detector's UTC grouping; rhythm fed full history (never the 50-slice); funding labels use SharedSummary preferred currency while totals use the model's `currency` arg; partial-failure error semantics (rhythm best-effort, the rest preserve prior rows on throw).

---

## File structure

| File | Change |
|------|--------|
| `Sources/GoldengoData/IngestionStore.swift` | Add cache stored props + `LedgerFingerprint` + `allocateCached` + `fingerprint`; make `makeSnapshot` internal |
| `Sources/GoldengoData/IngestionStore+Provenance.swift` | Extract `buildAllocatorInputs` + `fundingLabelMap`; route `compute` through `allocateCached` |
| `Sources/GoldengoData/IngestionStore+Dashboard.swift` | Extract `makeDashboardSummary(monthRecords:...)`; `dashboardSummary` delegates |
| `Sources/GoldengoData/IngestionStore+Rhythm.swift` | Extract `rhythmGhosts(from:now:)` with a **batched** merchant fetch; delete dead `learnedCategoryName`; public `rhythmGhosts(now:)` delegates |
| `Sources/GoldengoData/IngestionStore+HomeData.swift` | **New** — `HomeData` struct + `homeData(...)` |
| `Sources/GoldengoData/RecentExpensesReading.swift` | Add `homeData(...)` to the protocol |
| `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift` | `load()` calls `homeData(...)` |
| `Tests/GoldengoDataTests/AllocationCacheTests.swift` | **New** — cache hit / miss-on-mutation / miss-on-currency-change |
| `Tests/GoldengoDataTests/HomeDataParityTests.swift` | **New** — `homeData` == the four granular methods |
| `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift` | Add `homeData` to `FailingReader` |

---

## Task 1: Fingerprint-keyed FIFO allocation cache

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift` (add cache state + helpers, after the `@ModelActor public actor IngestionStore {` line ~34)
- Modify: `Sources/GoldengoData/IngestionStore+Provenance.swift` (extract `buildAllocatorInputs`; route `compute` through the cache)
- Test: `Tests/GoldengoDataTests/AllocationCacheTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoDataTests/AllocationCacheTests.swift`:

```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class AllocationCacheTests: XCTestCase {
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    func test_allocation_reusedWhenNothingChanged() async throws {
        let store = try makeStore()
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister")
        try await store.logManual(amount: 200, currency: .all, merchant: "Coffee", categoryName: nil)
        _ = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let after1 = await store.allocationComputeCount
        _ = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let after2 = await store.allocationComputeCount
        XCTAssertEqual(after1, 1, "First snapshot is a cache miss → exactly one allocation.")
        XCTAssertEqual(after2, 1, "No mutation between calls → reuse the cache, not recompute.")
    }

    func test_allocation_recomputesAfterMutation_andReflectsIt() async throws {
        let store = try makeStore()
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister")
        _ = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let before = await store.allocationComputeCount
        try await store.logManual(amount: 300, currency: .all, merchant: "Coffee", categoryName: nil)
        let snap = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let after = await store.allocationComputeCount
        XCTAssertGreaterThan(after, before, "A new spend changes the fingerprint → recompute.")
        XCTAssertEqual(snap.sources.first { $0.name == "Sister" }?.remaining, 700, "Recompute reflects the spend.")
    }

    func test_allocation_recomputesOnCurrencyChange() async throws {
        let store = try makeStore()
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister")
        _ = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let a = await store.allocationComputeCount
        _ = try await store.provenanceSnapshot(displayCurrency: CurrencyCode("EUR"), rates: SeedRates.table)
        let b = await store.allocationComputeCount
        XCTAssertGreaterThan(b, a, "A different display currency is a different fingerprint → recompute.")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AllocationCacheTests`
Expected: FAIL — `value of type 'IngestionStore' has no member 'allocationComputeCount'`.

- [ ] **Step 3: Add the cache state + helpers to `IngestionStore.swift`**

In `Sources/GoldengoData/IngestionStore.swift`, immediately after the line `public actor IngestionStore {` (line 34), insert:

```swift
    // MARK: FIFO allocation cache (GOL-86)
    // Memoize the ProvenanceAllocator result. The allocation depends ONLY on the provenance inputs +
    // display currency + rate date, so we key the cache on a content fingerprint of those — it can
    // never serve stale data: any local edit/delete/add-income, a date reorder, a currency/rate
    // change, or a CloudKit remote merge changes the fingerprint and forces a recompute. Internal (not
    // private) so the cross-file +Provenance / +HomeData extensions can call allocateCached.
    struct LedgerFingerprint: Equatable {
        let currencyCode: String
        let ratesAsOf: Date
        let inflowKeys: [String]
        let outflowKeys: [String]
    }
    private var cachedAllocation: (fingerprint: LedgerFingerprint, allocation: ProvenanceAllocator.Allocation)?
    /// Test observability only: number of times the allocator actually ran (i.e. cache misses).
    private(set) var allocationComputeCount = 0

    /// Reuse the cached allocation when the inputs+currency+rate-date are identical, else recompute.
    func allocateCached(inflows: [ProvenanceAllocator.Inflow], outflows: [ProvenanceAllocator.Outflow],
                        rates: RateTable, displayCurrency: CurrencyCode) -> ProvenanceAllocator.Allocation {
        let fp = fingerprint(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: displayCurrency)
        if let cached = cachedAllocation, cached.fingerprint == fp { return cached.allocation }
        let alloc = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows,
                                                 rates: rates, displayCurrency: displayCurrency)
        cachedAllocation = (fp, alloc)
        allocationComputeCount += 1
        return alloc
    }

    /// Order-independent content fingerprint of the allocator inputs (keys sorted so a different fetch
    /// order — e.g. Home's date-desc vs Sources' unsorted — still hits the same cache entry).
    private func fingerprint(inflows: [ProvenanceAllocator.Inflow], outflows: [ProvenanceAllocator.Outflow],
                             rates: RateTable, displayCurrency: CurrencyCode) -> LedgerFingerprint {
        LedgerFingerprint(
            currencyCode: displayCurrency.rawValue,
            ratesAsOf: rates.asOf,
            inflowKeys: inflows.map { "\($0.id)|\($0.date.timeIntervalSinceReferenceDate)|\($0.amount)|\($0.currency.rawValue)|\($0.sourceID)" }.sorted(),
            outflowKeys: outflows.map { "\($0.id)|\($0.date.timeIntervalSinceReferenceDate)|\($0.amount)|\($0.currency.rawValue)" }.sorted())
    }
```

- [ ] **Step 4: Route `compute` through the cache + extract `buildAllocatorInputs`**

In `Sources/GoldengoData/IngestionStore+Provenance.swift`, replace the `compute(rates:displayCurrency:)` method (lines 82-105) with:

```swift
    /// Build allocator inputs (income → inflows, expense → outflows) from non-archived records.
    /// Internal so `homeData` can reuse a single shared fetch instead of re-fetching.
    func buildAllocatorInputs(from records: [ExpenseRecord])
        -> (inflows: [ProvenanceAllocator.Inflow], outflows: [ProvenanceAllocator.Outflow]) {
        let incomeRaw = TransactionKind.income.rawValue
        let expenseRaw = TransactionKind.expense.rawValue
        var inflows: [ProvenanceAllocator.Inflow] = []
        var outflows: [ProvenanceAllocator.Outflow] = []
        for r in records {
            if r.kindRaw == incomeRaw, let sid = r.provenanceSource?.id {
                inflows.append(.init(id: r.dedupeKey, sourceID: sid, amount: r.amount,
                                     currency: CurrencyCode(r.currencyCode), date: r.date))
            } else if r.kindRaw == expenseRaw {
                outflows.append(.init(id: r.dedupeKey, amount: r.amount,
                                      currency: CurrencyCode(r.currencyCode), date: r.date))
            }
        }
        return (inflows, outflows)
    }

    /// Build allocator inputs from non-archived records and run it (via the fingerprint cache).
    /// Shared by snapshot + labels.
    private func compute(rates: RateTable, displayCurrency: CurrencyCode)
        throws -> (ProvenanceAllocator.Allocation, [SourceRecord]) {
        let sources = try modelContext.fetch(FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        let records = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        let (inflows, outflows) = buildAllocatorInputs(from: records)
        let alloc = allocateCached(inflows: inflows, outflows: outflows,
                                   rates: rates, displayCurrency: displayCurrency)
        return (alloc, sources)
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter AllocationCacheTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoData/IngestionStore.swift Sources/GoldengoData/IngestionStore+Provenance.swift Tests/GoldengoDataTests/AllocationCacheTests.swift
git commit -m "feat(gol-86): fingerprint-keyed FIFO allocation cache"
```

---

## Task 2: Extract shared derivation helpers (refactor under existing tests)

Behavior-preserving extractions so `homeData` (Task 3) can derive everything from one fetch. The existing provenance/dashboard/rhythm test suites are the safety net; Task 3's parity test is the new behavioral gate.

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift` (make `makeSnapshot` internal)
- Modify: `Sources/GoldengoData/IngestionStore+Provenance.swift` (extract `fundingLabelMap`)
- Modify: `Sources/GoldengoData/IngestionStore+Dashboard.swift` (extract `makeDashboardSummary`)
- Modify: `Sources/GoldengoData/IngestionStore+Rhythm.swift` (extract `rhythmGhosts(from:now:)` with batched merchant fetch; remove dead `learnedCategoryName`)

- [ ] **Step 1: Make `makeSnapshot` internal**

In `Sources/GoldengoData/IngestionStore.swift` line 164, change:

```swift
    private func makeSnapshot(_ r: ExpenseRecord) -> ExpenseSnapshot {
```
to (remove `private` so the `+HomeData` extension can call it):
```swift
    func makeSnapshot(_ r: ExpenseRecord) -> ExpenseSnapshot {
```

- [ ] **Step 2: Extract `fundingLabelMap` and have `fundingLabels` delegate**

In `Sources/GoldengoData/IngestionStore+Provenance.swift`, replace the `fundingLabels(displayCurrency:)` method (lines 69-80) with:

```swift
    /// dedupeKey -> "funded by" label (e.g. "Sister" or "Sister, Cash"), for expense rows.
    func fundingLabels(displayCurrency: CurrencyCode) throws -> [String: String] {
        let table = ExchangeRateCache().load() ?? SeedRates.table
        let (alloc, sources) = try compute(rates: table, displayCurrency: displayCurrency)
        return fundingLabelMap(alloc: alloc, sources: sources)
    }

    /// Map a finished allocation + its sources into per-outflow "funded by" label strings.
    /// Internal so `homeData` can reuse it from its single shared fetch.
    func fundingLabelMap(alloc: ProvenanceAllocator.Allocation, sources: [SourceRecord]) -> [String: String] {
        let nameByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.name) })
        var labels: [String: String] = [:]
        for (outflowID, segs) in alloc.fundingByOutflow {
            let names = segs.compactMap { nameByID[$0.sourceID] }
            if !names.isEmpty { labels[outflowID] = names.joined(separator: ", ") }
        }
        return labels
    }
```

- [ ] **Step 3: Extract `makeDashboardSummary` and have `dashboardSummary` delegate**

In `Sources/GoldengoData/IngestionStore+Dashboard.swift`, replace the `dashboardSummary(in:rates:now:topCategoryLimit:)` method (lines 33-74) with:

```swift
    /// Aggregates the current month's spend, top categories, and the confirmed-subscription monthly
    /// equivalent — converting every expense into `displayCurrency` via `rates`.
    public func dashboardSummary(in displayCurrency: CurrencyCode = .all, rates: RateTable,
                                 now: Date = .now, topCategoryLimit: Int = 4) throws -> DashboardSummary {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
        let expenseRaw = TransactionKind.expense.rawValue
        let monthRecords = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw && $0.date >= monthStart
        }))
        return try makeDashboardSummary(monthRecords: monthRecords, in: displayCurrency,
                                        rates: rates, topCategoryLimit: topCategoryLimit)
    }

    /// Reduce already-fetched month expense records + confirmed subscriptions into a DashboardSummary.
    /// Internal so `homeData` can pass a month-filtered slice of its single shared fetch.
    func makeDashboardSummary(monthRecords: [ExpenseRecord], in displayCurrency: CurrencyCode,
                              rates: RateTable, topCategoryLimit: Int) throws -> DashboardSummary {
        let converter = CurrencyConverter(table: rates)
        let display = displayCurrency.rawValue

        var monthTotal = Decimal(0)
        var byCategory: [String: Decimal] = [:]
        var usedConversion = false
        for r in monthRecords {
            if r.currencyCode != display { usedConversion = true }
            let v = (try? converter.convert(r.amount, from: CurrencyCode(r.currencyCode), to: displayCurrency)) ?? 0
            monthTotal += v
            byCategory[r.category?.name ?? "Other", default: 0] += v
        }
        let topCategories = byCategory
            .map { CategoryTotal(name: $0.key, total: $0.value) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
            .prefix(topCategoryLimit).map { $0 }

        let confirmed = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>(predicate: #Predicate {
            $0.isConfirmed == true && $0.isDismissed == false && $0.isArchived == false
        }))
        let subsMonthly = confirmed.reduce(Decimal(0)) { acc, sub in
            if sub.currencyCode != display { usedConversion = true }
            let monthlyEq = Self.monthlyEquivalent(sub.amount, cadence: sub.cadence)
            let v = (try? converter.convert(monthlyEq, from: CurrencyCode(sub.currencyCode), to: displayCurrency)) ?? 0
            return acc + v
        }

        return DashboardSummary(monthTotal: monthTotal, topCategories: topCategories,
                                confirmedSubscriptionCount: confirmed.count,
                                confirmedSubscriptionsMonthly: subsMonthly,
                                currencyCode: display, ratesAsOf: usedConversion ? rates.asOf : nil)
    }
```

- [ ] **Step 4: Extract `rhythmGhosts(from:now:)` with a batched merchant fetch; delete dead `learnedCategoryName`**

In `Sources/GoldengoData/IngestionStore+Rhythm.swift`, replace the `rhythmGhosts(now:)` method (lines 17-42) and the private `learnedCategoryName(forNormalized:)` method (lines 53-58) with:

```swift
    /// Today's pre-drafted "usuals": active daily patterns NOT yet logged today. Computed each call.
    public func rhythmGhosts(now: Date = .now) throws -> [RhythmGhost] {
        let expenseRaw = TransactionKind.expense.rawValue
        let expenses = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.kindRaw == expenseRaw }))
        return try rhythmGhosts(from: expenses, now: now)
    }

    /// Derive ghosts from already-fetched non-archived expense records. Internal so `homeData` can
    /// reuse its single shared fetch. Batches the per-ghost merchant-category lookup into ONE fetch.
    func rhythmGhosts(from expenses: [ExpenseRecord], now: Date) throws -> [RhythmGhost] {
        let occurrences = expenses.map {
            TransactionOccurrence(id: $0.dedupeKey, date: $0.date, amount: abs($0.amount),
                                  currency: CurrencyCode($0.currencyCode), merchant: $0.merchantName)
        }
        let patterns = RhythmDetector.detect(occurrences, options: .init(now: now))

        // Merchants already logged today → suppress (no double-count). Deliberately the LOCAL day
        // (the user's "today"), even though RhythmDetector groups by UTC day — don't "align" them:
        // confirmRhythmGhost writes date:.now, so a just-confirmed ghost is always caught by this
        // local-day filter on the next recompute (the suppression invariant).
        let startOfToday = Calendar.current.startOfDay(for: now)
        let loggedTodayMerchants = Set(expenses
            .filter { $0.date >= startOfToday }
            .map { MerchantNormalizer.normalize($0.merchantName) })
        let surfaced = patterns.filter { !loggedTodayMerchants.contains($0.normalizedMerchant) }

        // One fetch for all surfaced ghosts' learned categories (replaces the per-ghost N+1).
        let norms = surfaced.map(\.normalizedMerchant)
        let merchants = norms.isEmpty ? [] : try modelContext.fetch(FetchDescriptor<MerchantRecord>(
            predicate: #Predicate { norms.contains($0.normalizedName) }))
        let categoryByNorm = Dictionary(merchants.map { ($0.normalizedName, $0.defaultCategory?.name) },
                                        uniquingKeysWith: { first, _ in first })

        return surfaced.map { p in
            RhythmGhost(id: p.id, displayName: p.displayName, normalizedMerchant: p.normalizedMerchant,
                        amount: p.amount, currencyCode: p.currency.rawValue,
                        categoryName: categoryByNorm[p.normalizedMerchant] ?? nil)
        }
    }
```

- [ ] **Step 5: Build + run the affected suites to prove parity**

Run: `swift build && swift test --filter ProvenanceStoreTests && swift test --filter RhythmGhostTests && swift test --filter DashboardSummaryTests`
Expected: Build complete; all three suites PASS (behavior preserved by the extractions).

(If a `DashboardSummaryTests` target name differs, run the full `swift test` — the goal is green dashboard/rhythm/provenance tests.)

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoData/IngestionStore.swift Sources/GoldengoData/IngestionStore+Provenance.swift Sources/GoldengoData/IngestionStore+Dashboard.swift Sources/GoldengoData/IngestionStore+Rhythm.swift
git commit -m "refactor(gol-86): extract shared derivation helpers + batch ghost merchant fetch"
```

---

## Task 3: `homeData(...)` — one fetch, in-memory derivation

**Files:**
- Create: `Sources/GoldengoData/IngestionStore+HomeData.swift`
- Modify: `Sources/GoldengoData/RecentExpensesReading.swift` (add to protocol)
- Test: `Tests/GoldengoDataTests/HomeDataParityTests.swift`

- [ ] **Step 1: Write the failing parity test**

Create `Tests/GoldengoDataTests/HomeDataParityTests.swift`:

```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class HomeDataParityTests: XCTestCase {
    func test_homeData_matchesGranularMethods() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        // Income source, a today expense, and a 7-day daily pattern (yields a ghost), mixed kinds.
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister")
        try await store.logManual(amount: 200, currency: .all, merchant: "Coffee", categoryName: "Coffee", date: .now)
        for k in stride(from: 7, through: 1, by: -1) {
            try await store.logManual(amount: 150, currency: .all, merchant: "Bus", categoryName: nil,
                                      date: Date().addingTimeInterval(Double(-k) * 86_400))
        }
        let rates = SeedRates.table
        let now = Date()

        let data = try await store.homeData(in: .all, rates: rates, now: now, topCategoryLimit: 4)
        let recent = try await store.recentExpenses(limit: 50)
        let today = try await store.todayTotal(in: .all, rates: rates)
        let summary = try await store.dashboardSummary(in: .all, rates: rates, now: now, topCategoryLimit: 4)
        let ghosts = try await store.rhythmGhosts(now: now)

        XCTAssertEqual(data.rows, recent, "recent rows (incl. fundedBy) must match recentExpenses")
        XCTAssertEqual(data.todayTotal, today, "today total must match todayTotal")
        XCTAssertEqual(data.summary, summary, "summary must match dashboardSummary")
        XCTAssertEqual(data.ghosts, ghosts, "ghosts must match rhythmGhosts")
        XCTAssertTrue(data.ghosts.contains { $0.displayName == "Bus" }, "the daily pattern surfaces a ghost")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter HomeDataParityTests`
Expected: FAIL — `value of type 'IngestionStore' has no member 'homeData'`.

- [ ] **Step 3: Create `IngestionStore+HomeData.swift`**

Create `Sources/GoldengoData/IngestionStore+HomeData.swift`:

```swift
import Foundation
import SwiftData
import GoldengoCore

/// Everything the Home dashboard needs, from ONE expense fetch. Sendable value snapshot.
public struct HomeData: Sendable {
    public let rows: [ExpenseSnapshot]      // recent 50 (both kinds), expense rows carry fundedBy
    public let todayTotal: Decimal          // displayCurrency
    public let summary: DashboardSummary
    public let ghosts: [RhythmGhost]
}

extension IngestionStore {
    /// One fetch of all non-archived expense records → derive recent-50 / today total / month summary
    /// / rhythm ghosts in memory (replacing the four separate reader calls + their redundant scans).
    /// Funding labels use the SharedSummary preferred currency (matching `recentExpenses`); the totals
    /// use `displayCurrency`. The FIFO allocation goes through the fingerprint cache.
    public func homeData(in displayCurrency: CurrencyCode = .all, rates: RateTable,
                         now: Date = .now, topCategoryLimit: Int = 4) throws -> HomeData {
        let expenseRaw = TransactionKind.expense.rawValue

        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.relationshipKeyPathsForPrefetching = [\.category, \.subscription, \.provenanceSource]
        let all = try modelContext.fetch(fd)
        let sources = try modelContext.fetch(FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.isArchived == false }))

        // Provenance funding labels — preferred currency, via the cached allocation.
        let (inflows, outflows) = buildAllocatorInputs(from: all)
        let alloc = allocateCached(inflows: inflows, outflows: outflows, rates: rates,
                                   displayCurrency: SharedSummary().readPreferredCurrency())
        let labels = fundingLabelMap(alloc: alloc, sources: sources)

        // Recent 50 (both kinds, already date-desc); attach fundedBy to expense rows.
        let rows: [ExpenseSnapshot] = all.prefix(50).map { r in
            var snap = makeSnapshot(r)
            if r.kindRaw == expenseRaw { snap.fundedBy = labels[r.dedupeKey] }
            return snap
        }

        // Today total (displayCurrency).
        let startOfToday = Calendar.current.startOfDay(for: now)
        let todayMonies = all
            .filter { $0.kindRaw == expenseRaw && $0.date >= startOfToday }
            .map { Money(amount: $0.amount, currency: CurrencyCode($0.currencyCode)) }
        let todayTotal = CurrencyConverter(table: rates).sum(todayMonies, to: displayCurrency)

        // Month summary (displayCurrency) from a month-filtered slice of the same array.
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
        let monthRecords = all.filter { $0.kindRaw == expenseRaw && $0.date >= monthStart }
        let summary = try makeDashboardSummary(monthRecords: monthRecords, in: displayCurrency,
                                               rates: rates, topCategoryLimit: topCategoryLimit)

        // Ghosts — best-effort so a rhythm failure never blanks the dashboard (matches load()'s try?).
        let ghosts = (try? rhythmGhosts(from: all.filter { $0.kindRaw == expenseRaw }, now: now)) ?? []

        return HomeData(rows: rows, todayTotal: todayTotal, summary: summary, ghosts: ghosts)
    }
}
```

- [ ] **Step 4: Add `homeData` to the `RecentExpensesReading` protocol AND the `FailingReader` mock**

In `Sources/GoldengoData/RecentExpensesReading.swift`, add this line inside the protocol body (after the `rhythmGhosts`/`confirmRhythmGhost` lines, before the closing `}`):

```swift
    func homeData(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> HomeData
```

Adding a protocol requirement makes the test mock `FailingReader` (in `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift`) non-conforming, which breaks the whole test build. Add the matching stub now (inside `FailingReader`, after its `confirmRhythmGhost` line):

```swift
    func homeData(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> HomeData { throw Boom() }
```

- [ ] **Step 5: Run the parity test to verify it passes**

Run: `swift test --filter HomeDataParityTests`
Expected: PASS (and the whole test build compiles — `FailingReader` now conforms).

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoData/IngestionStore+HomeData.swift Sources/GoldengoData/RecentExpensesReading.swift Tests/GoldengoDataTests/HomeDataParityTests.swift Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift
git commit -m "feat(gol-86): homeData single-fetch consolidation + protocol method"
```

---

## Task 4: `RecentExpensesModel.load()` uses `homeData`

**Files:**
- Modify: `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift`

(The `FailingReader` mock already gained `homeData` in Task 3 Step 4.)

- [ ] **Step 1: Switch `load()` to the single `homeData` call**

In `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift`, replace the `load()` method (lines 23-37) with:

```swift
    public func load() async {
        do {
            let rates = ExchangeRateCache().load() ?? SeedRates.table
            let data = try await reader.homeData(in: currency, rates: rates, now: .now, topCategoryLimit: 4)
            rows = data.rows
            todayTotalText = Money(amount: data.todayTotal, currency: currency).formatted()
            summary = data.summary
            ghosts = data.ghosts
            loadFailed = false
        } catch {
            // Keep any previously-loaded rows on screen; surface the failure so the user can retry.
            loadFailed = true
        }
    }
```

- [ ] **Step 2: Run the model tests to verify they pass**

Run: `swift test --filter RecentExpensesModelTests`
Expected: PASS — `test_load_populatesRowsAndTodayTotal` (rows=1, todayTotalText "ALL 250", summary non-nil) and `test_load_failure_setsLoadFailed_andDoesNotClobberRows` (FailingReader.homeData throws → loadFailed, rows empty, summary nil).

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift
git commit -m "feat(gol-86): RecentExpensesModel.load() uses single homeData call"
```

---

## Task 5: Full verification + review + ship

**Files:** none (verification + release).

- [ ] **Step 1: Full suite**

Run: `swift test`
Expected: ALL pass (prior 278 + new AllocationCache ×3 + HomeDataParity ×1). No SIGSEGV (the Decimal-in-#Predicate guard). Fix anything red before proceeding.

- [ ] **Step 2: Simulator build**

Run:
```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath AppProject/.build build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Second-Opus adversarial review of the diff**

Review `git diff main...HEAD`: verify the parity (homeData == granular), the cache can't go stale (fingerprint covers edits/deletes/date-reorder/currency/rate/CloudKit), no Decimal entered a `#Predicate`, only Sendable crosses the actor boundary, and the partial-failure error semantics are unchanged. Address Critical/Major before merge.

- [ ] **Step 4: Device build + install (if the iPhone is reachable)**

```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -derivedDataPath AppProject/.build-device build
xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E \
  AppProject/.build-device/Build/Products/Debug-iphoneos/Goldengo.app
```
If the device is unavailable, note it and proceed (verification is behavioral parity — covered by tests).

- [ ] **Step 5: Merge to main + push, set GOL-86 → To Verify**

ff-merge `gol-86-home-load-perf` into `main`, push, delete the branch, and move GOL-86 to **To Verify** with a summary (what consolidated, the cache design, parity-tested, the honest O(expenses) bound).

---

## Self-review notes (author)

**Spec coverage:** consolidation `homeData` (Task 3) ✓ · fingerprint cache (Task 1) ✓ · batched merchant fetch (Task 2) ✓ · relationship prefetch (Task 3 fd) ✓ · model 1-round-trip (Task 4) ✓ · parity + cache + error-semantics tests (Tasks 1/3/4) ✓.

**Type consistency:** `allocateCached(inflows:outflows:rates:displayCurrency:)`/`LedgerFingerprint`/`allocationComputeCount` defined Task 1, used by `compute` (Task 1) and `homeData` (Task 3). `buildAllocatorInputs(from:)` (Task 1) + `fundingLabelMap(alloc:sources:)` (Task 2) + `makeDashboardSummary(monthRecords:in:rates:topCategoryLimit:)` (Task 2) + `rhythmGhosts(from:now:)` (Task 2) + internal `makeSnapshot` (Task 2) all consumed by `homeData` (Task 3). `HomeData`/`homeData(in:rates:now:topCategoryLimit:)` defined Task 3, added to protocol (Task 3) + `FailingReader` (Task 4) + used by `load()` (Task 4).

**Swift correctness:** stored cache state lives on the `actor` body (not an extension); cross-file helpers are `internal` (not `private`) so the `+Provenance`/`+Dashboard`/`+Rhythm`/`+HomeData` extensions can call them; the cache stores the pure Sendable `Allocation`, never `@Model`s; the batched merchant predicate uses a String `contains` (no Decimal).

**Parity caveats handled:** `homeData` row set = `all.prefix(50)` (date-desc) == `recentExpenses(limit:50)`; funding-label currency = SharedSummary preferred (both paths); ghost/today/month derivations use the same filters/now as the granular methods; the parity test passes a single `now` to both sides to avoid a midnight-boundary flake.
