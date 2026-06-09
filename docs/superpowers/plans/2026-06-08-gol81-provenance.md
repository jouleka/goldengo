# Provenance (GOL-81) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Money carries its origin — the user logs named inflows ("€200 from Sister"), each becomes a colored Source, and a deterministic in-memory FIFO allocator drains the oldest source first as they spend, surfaced as draining balances + a "funded by …" line.

**Architecture:** A pure `ProvenanceAllocator` (GoldengoCore) does FIFO drawdown with on-device currency conversion. A `SourceRecord` SwiftData model holds named origins; income records link to it. `IngestionStore` gains income capture + a provenance computation that powers a new Sources tab and a `fundedBy` field on existing Recent rows. No backend.

**Tech Stack:** Swift 6, SwiftUI, SwiftData (+CloudKit), `CurrencyConverter`/`RateTable`, XCTest. Spec: `docs/superpowers/specs/2026-06-08-provenance-design.md`.

**Cross-platform:** all of this is cross-platform (no iOS-only APIs); the package builds + tests on macOS. `Decimal` math stays in plain Swift, never in a `#Predicate` (segfault rule).

---

## File Structure

**Create:**
- `Sources/GoldengoData/Models/SourceRecord.swift` — the named-origin model.
- `Sources/GoldengoCore/ProvenanceAllocator.swift` — pure FIFO allocator + value types.
- `Sources/GoldengoData/IngestionStore+Provenance.swift` — `logIncome`, `findOrCreateSource`, `sources()`, `provenanceSnapshot`, funding computation (extension of the `@ModelActor`).
- `Sources/GoldengoFeatures/Provenance/SourcesModel.swift` + `SourcesView.swift` + `AddIncomeView.swift`.
- `Tests/GoldengoCoreTests/ProvenanceAllocatorTests.swift`
- `Tests/GoldengoDataTests/ProvenanceStoreTests.swift`

**Modify:**
- `Sources/GoldengoData/Models/ExpenseRecord.swift` — add `provenanceSource: SourceRecord?`.
- `Sources/GoldengoData/ModelContainer+Goldengo.swift` — register `SourceRecord`.
- `Sources/GoldengoData/IngestionStore.swift` — add `fundedBy` to `ExpenseSnapshot`; populate it in `recentExpenses`.
- `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift` — show the "funded by" line.
- `Sources/GoldengoFeatures/RootView.swift` — add the Sources tab.

---

## Task 1: `SourceRecord` model + `ExpenseRecord.provenanceSource` + schema

**Files:** Create `Sources/GoldengoData/Models/SourceRecord.swift`; Modify `ExpenseRecord.swift`, `ModelContainer+Goldengo.swift`; Test `Tests/GoldengoDataTests/ProvenanceStoreTests.swift`.

- [ ] **Step 1: Write the failing test** — create `Tests/GoldengoDataTests/ProvenanceStoreTests.swift`:

```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class ProvenanceStoreTests: XCTestCase {
    func test_sourceRecord_linksIncomeViaProvenanceRelationship() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        let src = SourceRecord(id: "s1", name: "Sister", currencyCode: "EUR", colorIndex: 0)
        ctx.insert(src)
        let inc = ExpenseRecord(amount: 200, currencyCode: "EUR", date: .now,
                                kind: .income, source: .manual, dedupeKey: "income:1")
        inc.provenanceSource = src
        ctx.insert(inc)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<SourceRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.incomes?.count, 1)
        XCTAssertEqual(fetched.first?.incomes?.first?.amount, 200)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'ProvenanceStoreTests/test_sourceRecord_linksIncomeViaProvenanceRelationship'`
Expected: FAIL — `cannot find 'SourceRecord' in scope`.

- [ ] **Step 3: Create `SourceRecord`** — `Sources/GoldengoData/Models/SourceRecord.swift`:

```swift
import Foundation
import SwiftData

/// A named money origin ("Sister", "Freelance", "Friday cash"). Income records link to it;
/// expenses draw from sources via the pure FIFO allocator (never stored).
@Model
public final class SourceRecord {
    public var id: String = ""                 // stable UUID string — the allocator's sourceID (rename-safe)
    public var name: String = ""
    public var currencyCode: String = "ALL"    // the source's native currency
    public var colorIndex: Int = 0             // palette slot for the distinct color
    public var createdAt: Date = Date.now
    public var isArchived: Bool = false        // soft-delete tombstone (CloudKit-friendly)
    // Inverse of ExpenseRecord.provenanceSource. REQUIRED for CloudKit (cf. AccountRecord).
    @Relationship(deleteRule: .nullify, inverse: \ExpenseRecord.provenanceSource)
    public var incomes: [ExpenseRecord]? = []

    public init(id: String = UUID().uuidString, name: String = "", currencyCode: String = "ALL",
                colorIndex: Int = 0, createdAt: Date = .now, isArchived: Bool = false) {
        self.id = id; self.name = name; self.currencyCode = currencyCode
        self.colorIndex = colorIndex; self.createdAt = createdAt; self.isArchived = isArchived
    }
}
```

- [ ] **Step 4: Add the relationship to `ExpenseRecord`** — in `Sources/GoldengoData/Models/ExpenseRecord.swift`, add this stored property after `public var subscription: SubscriptionRecord?` (line 22), NOT in the init (set by `logIncome`, like `subscription`/`category`):

```swift
    // The named money source this INCOME record belongs to (nil for expenses + un-sourced income).
    // Set by logIncome, not in init. Inverse declared on SourceRecord.incomes.
    public var provenanceSource: SourceRecord?
```

- [ ] **Step 5: Register in the schema** — in `Sources/GoldengoData/ModelContainer+Goldengo.swift`, add `SourceRecord.self` to the `Schema([...])` list:

```swift
        Schema([
            ExpenseRecord.self, CategoryRecord.self, AccountRecord.self, MerchantRecord.self,
            ImportBatch.self, SubscriptionRecord.self, SourceRecord.self,
        ])
```

- [ ] **Step 6: Run to verify it passes**

Run: `swift test --filter 'ProvenanceStoreTests'`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/GoldengoData/Models/SourceRecord.swift Sources/GoldengoData/Models/ExpenseRecord.swift Sources/GoldengoData/ModelContainer+Goldengo.swift Tests/GoldengoDataTests/ProvenanceStoreTests.swift
git commit -m "feat(gol-81): SourceRecord model + ExpenseRecord.provenanceSource + schema"
```

---

## Task 2: `ProvenanceAllocator` (pure FIFO core)

**Files:** Create `Sources/GoldengoCore/ProvenanceAllocator.swift`; Test `Tests/GoldengoCoreTests/ProvenanceAllocatorTests.swift`.

- [ ] **Step 1: Write the failing tests** — create `Tests/GoldengoCoreTests/ProvenanceAllocatorTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class ProvenanceAllocatorTests: XCTestCase {
    // 1 EUR = 100 ALL, 1 USD = 100 ALL (base USD).
    private let rates = RateTable(base: CurrencyCode("USD"),
                                  rates: ["USD": 1, "ALL": 100, "EUR": 1],
                                  asOf: Date(timeIntervalSince1970: 1_780_000_000))
    private func d(_ s: String) -> Decimal { Decimal(string: s)! }
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(n) * 86_400) }

    func test_fifo_drainsOldestSourceFirst() {
        let inflows = [
            ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 1000, currency: .all, date: day(0)),
            ProvenanceAllocator.Inflow(id: "i2", sourceID: "B", amount: 1000, currency: .all, date: day(2)),
        ]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 600, currency: .all, date: day(3))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.remainingBySource["A"], 400)   // oldest drained
        XCTAssertEqual(a.remainingBySource["B"], 1000)  // newer untouched
        XCTAssertEqual(a.fundingByOutflow["o1"], [.init(sourceID: "A", amount: 600)])
        XCTAssertEqual(a.totalUnaccounted, 0)
    }

    func test_outflow_spansTwoLots() {
        let inflows = [
            ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 500, currency: .all, date: day(0)),
            ProvenanceAllocator.Inflow(id: "i2", sourceID: "B", amount: 500, currency: .all, date: day(1)),
        ]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 800, currency: .all, date: day(2))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.remainingBySource["A"], 0)
        XCTAssertEqual(a.remainingBySource["B"], 200)
        XCTAssertEqual(a.fundingByOutflow["o1"], [.init(sourceID: "A", amount: 500), .init(sourceID: "B", amount: 300)])
    }

    func test_crossCurrency_eurSourceFundsLekSpend() {
        // Source A is EUR 10 (= 1000 ALL). A 250-ALL spend draws 2.50 EUR from A.
        let inflows = [ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 10, currency: .eur, date: day(0))]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 250, currency: .all, date: day(1))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.remainingBySource["A"], d("7.5"))
        XCTAssertEqual(a.fundingByOutflow["o1"], [.init(sourceID: "A", amount: d("2.5"))])
        XCTAssertEqual(a.totalUnaccounted, 0)
    }

    func test_overspend_goesToUnaccounted() {
        let inflows = [ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 100, currency: .all, date: day(0))]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 300, currency: .all, date: day(1))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.remainingBySource["A"], 0)
        XCTAssertEqual(a.totalUnaccounted, 200)
    }

    func test_expenseBeforeAnyInflow_isUnaccounted_noRetroactiveFunding() {
        let inflows = [ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 1000, currency: .all, date: day(5))]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 200, currency: .all, date: day(1))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.totalUnaccounted, 200)
        XCTAssertEqual(a.remainingBySource["A"], 1000)   // later income does NOT fund an earlier spend
        XCTAssertNil(a.fundingByOutflow["o1"])
    }

    func test_remaining_neverNegative_multiSource() {
        let inflows = [
            ProvenanceAllocator.Inflow(id: "i1", sourceID: "A", amount: 100, currency: .all, date: day(0)),
            ProvenanceAllocator.Inflow(id: "i2", sourceID: "A", amount: 100, currency: .all, date: day(1)),
            ProvenanceAllocator.Inflow(id: "i3", sourceID: "B", amount: 100, currency: .all, date: day(2)),
        ]
        let outflows = [ProvenanceAllocator.Outflow(id: "o1", amount: 250, currency: .all, date: day(3))]
        let a = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows, rates: rates, displayCurrency: .all)
        XCTAssertEqual(a.remainingBySource["A"], 0)    // both A lots drained (100+100)
        XCTAssertEqual(a.remainingBySource["B"], 50)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'ProvenanceAllocatorTests'`
Expected: FAIL — `cannot find 'ProvenanceAllocator' in scope`.

- [ ] **Step 3: Implement the allocator** — create `Sources/GoldengoCore/ProvenanceAllocator.swift`:

```swift
import Foundation

/// Pure, deterministic FIFO drawdown: spends draw from the oldest non-depleted inflow lot first,
/// converting currencies via `CurrencyConverter`. Value-in/value-out — no SwiftData, fully testable.
public enum ProvenanceAllocator {
    public struct Inflow: Sendable, Equatable {
        public let id: String; public let sourceID: String
        public let amount: Decimal; public let currency: CurrencyCode; public let date: Date
        public init(id: String, sourceID: String, amount: Decimal, currency: CurrencyCode, date: Date) {
            self.id = id; self.sourceID = sourceID; self.amount = amount; self.currency = currency; self.date = date
        }
    }
    public struct Outflow: Sendable, Equatable {
        public let id: String; public let amount: Decimal; public let currency: CurrencyCode; public let date: Date
        public init(id: String, amount: Decimal, currency: CurrencyCode, date: Date) {
            self.id = id; self.amount = amount; self.currency = currency; self.date = date
        }
    }
    public struct FundingSegment: Sendable, Equatable {
        public let sourceID: String; public let amount: Decimal   // in the SOURCE's currency
        public init(sourceID: String, amount: Decimal) { self.sourceID = sourceID; self.amount = amount }
    }
    public struct Allocation: Sendable, Equatable {
        public let remainingBySource: [String: Decimal]            // source currency, >= 0
        public let fundingByOutflow: [String: [FundingSegment]]
        public let totalUnaccounted: Decimal                       // in displayCurrency
    }

    public static func allocate(inflows: [Inflow], outflows: [Outflow],
                                rates: RateTable, displayCurrency: CurrencyCode) -> Allocation {
        let conv = CurrencyConverter(table: rates)
        let lots = inflows.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        var remaining: [String: Decimal] = [:]                     // by inflow.id
        for lot in lots { remaining[lot.id, default: 0] += lot.amount }

        var fundingByOutflow: [String: [FundingSegment]] = [:]
        var unaccounted: Decimal = 0

        for out in outflows.sorted(by: { ($0.date, $0.id) < ($1.date, $1.id) }) {
            var need = out.amount                                  // remaining need, in out.currency
            var segs: [FundingSegment] = []
            for lot in lots where need > 0 {
                let lotRem = remaining[lot.id] ?? 0
                if lotRem <= 0 { continue }
                guard let lotRemInOut = try? conv.convert(lotRem, from: lot.currency, to: out.currency) else { continue }
                let takenInOut = min(need, lotRemInOut)
                // If this lot is fully consumed, zero it exactly (avoid reconversion rounding drift).
                let fullyConsumes = takenInOut >= lotRemInOut
                let takenInLot = fullyConsumes ? lotRem
                    : ((try? conv.convert(takenInOut, from: out.currency, to: lot.currency)) ?? 0)
                remaining[lot.id] = lotRem - takenInLot
                need -= takenInOut
                segs.append(FundingSegment(sourceID: lot.sourceID, amount: takenInLot))
            }
            if need > 0 {
                unaccounted += (try? conv.convert(need, from: out.currency, to: displayCurrency)) ?? need
            }
            if !segs.isEmpty { fundingByOutflow[out.id] = merge(segs) }
        }

        var remainingBySource: [String: Decimal] = [:]
        for lot in lots { remainingBySource[lot.sourceID, default: 0] += (remaining[lot.id] ?? 0) }
        return Allocation(remainingBySource: remainingBySource,
                          fundingByOutflow: fundingByOutflow, totalUnaccounted: unaccounted)
    }

    /// Combine segments that hit the same source (an outflow can span two lots of one source).
    private static func merge(_ segs: [FundingSegment]) -> [FundingSegment] {
        var order: [String] = []
        var sums: [String: Decimal] = [:]
        for s in segs {
            if sums[s.sourceID] == nil { order.append(s.sourceID) }
            sums[s.sourceID, default: 0] += s.amount
        }
        return order.map { FundingSegment(sourceID: $0, amount: sums[$0] ?? 0) }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'ProvenanceAllocatorTests'`
Expected: PASS (all 6).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/ProvenanceAllocator.swift Tests/GoldengoCoreTests/ProvenanceAllocatorTests.swift
git commit -m "feat(gol-81): ProvenanceAllocator — pure FIFO drawdown with currency conversion"
```

---

## Task 3: `IngestionStore` income capture + provenance snapshot

**Files:** Create `Sources/GoldengoData/IngestionStore+Provenance.swift`; Modify `Sources/GoldengoData/IngestionStore.swift` (add `fundedBy` to `ExpenseSnapshot` + populate in `recentExpenses`); Test `Tests/GoldengoDataTests/ProvenanceStoreTests.swift`.

- [ ] **Step 1: Write the failing tests** — append to `ProvenanceStoreTests`:

```swift
    func test_logIncome_createsSourceAndLinkedIncome() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logIncome(amount: 200, currency: .eur, sourceName: "Sister", date: .now)
        let snap = try await store.provenanceSnapshot(displayCurrency: .all)
        XCTAssertEqual(snap.sources.count, 1)
        XCTAssertEqual(snap.sources.first?.name, "Sister")
        XCTAssertEqual(snap.sources.first?.remaining, 200)        // EUR, nothing spent yet
    }

    func test_findOrCreateSource_isCaseInsensitive() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logIncome(amount: 100, currency: .eur, sourceName: "Sister", date: .now)
        try await store.logIncome(amount: 50, currency: .eur, sourceName: "sister ", date: .now)
        let snap = try await store.provenanceSnapshot(displayCurrency: .all)
        XCTAssertEqual(snap.sources.count, 1, "Same source, two top-ups")
        XCTAssertEqual(snap.sources.first?.remaining, 150)
    }

    func test_provenanceSnapshot_drainsAndReportsFunding() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let rates = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1],
                              asOf: Date(timeIntervalSince1970: 1_780_000_000))
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Cash", date: Date(timeIntervalSince1970: 1_700_000_000))
        // Spend 300 ALL the next day.
        try await store.logManual(amount: 300, currency: .all, merchant: "Spar", categoryName: nil,
                                  date: Date(timeIntervalSince1970: 1_700_086_400))
        let snap = try await store.provenanceSnapshot(displayCurrency: .all, rates: rates)
        XCTAssertEqual(snap.sources.first?.remaining, 700)
        XCTAssertEqual(snap.unaccounted, 0)
        // The expense row carries a funded-by label.
        let recents = try await store.recentExpenses(limit: 10)
        let spend = recents.first { $0.kind == .expense }
        XCTAssertEqual(spend?.fundedBy, "Cash")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'ProvenanceStoreTests'`
Expected: FAIL — no `logIncome` / `provenanceSnapshot` / `fundedBy`.

- [ ] **Step 3: Add `fundedBy` to `ExpenseSnapshot`** — in `Sources/GoldengoData/IngestionStore.swift`, add this property to the `ExpenseSnapshot` struct (after `public var subscriptionName: String?`):

```swift
    /// Short "funded by …" label from provenance FIFO (nil for expenses with no named source, and
    /// for income rows). Populated by `recentExpenses`; defaults nil so other constructors are unaffected.
    public var fundedBy: String? = nil
```

- [ ] **Step 4: Populate it in `recentExpenses`** — in `IngestionStore.swift`, replace the `recentExpenses` method body with:

```swift
    public func recentExpenses(limit: Int = 20) throws -> [ExpenseSnapshot] {
        let labels = try fundingLabels(displayCurrency: SharedSummary().readPreferredCurrency())
        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = limit
        return try modelContext.fetch(fd).map { r in
            var snap = makeSnapshot(r)
            if r.kindRaw == TransactionKind.expense.rawValue { snap.fundedBy = labels[r.dedupeKey] }
            return snap
        }
    }
```

- [ ] **Step 5: Create the provenance extension** — `Sources/GoldengoData/IngestionStore+Provenance.swift`:

```swift
import Foundation
import SwiftData
import GoldengoCore

public struct SourceBalance: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let currencyCode: String
    public let colorIndex: Int
    public let totalInflow: Decimal     // source currency
    public let remaining: Decimal       // source currency, >= 0
}

public struct ProvenanceSnapshot: Sendable, Equatable {
    public let sources: [SourceBalance]
    public let unaccounted: Decimal     // displayCurrency
    public let displayCurrencyCode: String
}

extension IngestionStore {
    /// Find-or-create a source by case-insensitive name (mirrors findOrCreateCategory), then insert a
    /// linked `.income` record. A cash withdrawal / remittance / pay is just a named inflow.
    public func logIncome(amount: Decimal, currency: CurrencyCode,
                          sourceName: String, date: Date = .now) throws {
        let src = try findOrCreateSource(named: sourceName, currency: currency)
        let rec = ExpenseRecord(amount: amount, currencyCode: currency.rawValue, date: date,
                                merchantName: src.name, kind: .income, source: .manual,
                                dedupeKey: "income:\(UUID().uuidString)")
        rec.provenanceSource = src
        modelContext.insert(rec)
        try modelContext.save()
        try refreshSharedTodayTotal()
    }

    public func findOrCreateSource(named rawName: String, currency: CurrencyCode) throws -> SourceRecord {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = try modelContext.fetch(FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let colorIndex = all.count % 8
        let s = SourceRecord(name: name, currencyCode: currency.rawValue, colorIndex: colorIndex)
        modelContext.insert(s)
        return s
    }

    /// Per-source balances + Unaccounted, computed via the pure FIFO allocator.
    public func provenanceSnapshot(displayCurrency: CurrencyCode,
                                   rates: RateTable? = nil) throws -> ProvenanceSnapshot {
        let table = rates ?? (ExchangeRateCache().load() ?? SeedRates.table)
        let (alloc, sources) = try compute(rates: table, displayCurrency: displayCurrency)
        var totals: [String: Decimal] = [:]
        for s in sources { totals[s.id] = (s.incomes ?? []).filter { !$0.isArchived }
            .reduce(Decimal(0)) { $0 + $1.amount } }
        let balances = sources.map { s in
            SourceBalance(id: s.id, name: s.name, currencyCode: s.currencyCode, colorIndex: s.colorIndex,
                          totalInflow: totals[s.id] ?? 0,
                          remaining: max(0, alloc.remainingBySource[s.id] ?? 0))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return ProvenanceSnapshot(sources: balances, unaccounted: alloc.totalUnaccounted,
                                  displayCurrencyCode: displayCurrency.rawValue)
    }

    public func sources() throws -> [SourceRecord] {
        try modelContext.fetch(FetchDescriptor<SourceRecord>(predicate: #Predicate { $0.isArchived == false }))
    }

    /// dedupeKey -> "funded by" label (e.g. "Sister" or "Sister, Cash"), for expense rows.
    func fundingLabels(displayCurrency: CurrencyCode) throws -> [String: String] {
        let table = ExchangeRateCache().load() ?? SeedRates.table
        let (alloc, sources) = try compute(rates: table, displayCurrency: displayCurrency)
        let nameByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.name) })
        var labels: [String: String] = [:]
        for (outflowID, segs) in alloc.fundingByOutflow {
            let names = segs.compactMap { nameByID[$0.sourceID] }
            if !names.isEmpty { labels[outflowID] = names.joined(separator: ", ") }
        }
        return labels
    }

    /// Build allocator inputs from non-archived records and run it. Shared by snapshot + labels.
    private func compute(rates: RateTable, displayCurrency: CurrencyCode)
        throws -> (ProvenanceAllocator.Allocation, [SourceRecord]) {
        let sources = try modelContext.fetch(FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        let incomeRaw = TransactionKind.income.rawValue
        let expenseRaw = TransactionKind.expense.rawValue
        let records = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false }))
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
        let alloc = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows,
                                                 rates: rates, displayCurrency: displayCurrency)
        return (alloc, sources)
    }
}
```

- [ ] **Step 6: Run to verify it passes**

Run: `swift test --filter 'ProvenanceStoreTests'`
Expected: PASS.

- [ ] **Step 7: Run the full data suite (no regression — `recentExpenses` changed)**

Run: `swift test --filter 'GoldengoDataTests'`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/GoldengoData/IngestionStore+Provenance.swift Sources/GoldengoData/IngestionStore.swift Tests/GoldengoDataTests/ProvenanceStoreTests.swift
git commit -m "feat(gol-81): logIncome + provenanceSnapshot + fundedBy on Recent snapshots"
```

---

## Task 4: "funded by" line on Recent rows

**Files:** Modify `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`.

- [ ] **Step 1: Add the caption** — in `expenseRow(_:)`, replace the category line:

```swift
                Text(r.categoryName ?? "Other")
                    .font(.caption).foregroundStyle(.secondary)
```

with a category line plus an optional funded-by line:

```swift
                Text(r.categoryName ?? "Other")
                    .font(.caption).foregroundStyle(.secondary)
                if let fundedBy = r.fundedBy {
                    Label("funded by \(fundedBy)", systemImage: "arrow.down.left.circle")
                        .font(.caption2).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                }
```

- [ ] **Step 2: Build for the simulator**

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoFeatures/Recent/RecentExpensesView.swift
git commit -m "feat(gol-81): show 'funded by' line on Recent expense rows"
```

---

## Task 5: Sources screen + income capture

**Files:** Create `Sources/GoldengoFeatures/Provenance/SourcesModel.swift`, `SourcesView.swift`, `AddIncomeView.swift`; Test `Tests/GoldengoFeaturesTests/SourcesModelTests.swift`.

- [ ] **Step 1: Write the failing test** — create `Tests/GoldengoFeaturesTests/SourcesModelTests.swift`:

```swift
import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class SourcesModelTests: XCTestCase {
    func test_load_exposesSourceBalances() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logIncome(amount: 200, currency: .eur, sourceName: "Sister", date: .now)
        let model = SourcesModel(store: store, currency: .all)
        await model.load()
        XCTAssertEqual(model.snapshot?.sources.first?.name, "Sister")
        XCTAssertEqual(model.snapshot?.sources.first?.remaining, 200)
    }

    func test_addIncome_createsSource() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = SourcesModel(store: store, currency: .all)
        await model.addIncome(amount: 5000, currency: .all, sourceName: "Friday cash")
        await model.load()
        XCTAssertEqual(model.snapshot?.sources.count, 1)
        XCTAssertEqual(model.snapshot?.sources.first?.name, "Friday cash")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'SourcesModelTests'`
Expected: FAIL — `cannot find 'SourcesModel'`.

- [ ] **Step 3: Implement `SourcesModel`** — `Sources/GoldengoFeatures/Provenance/SourcesModel.swift`:

```swift
import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class SourcesModel {
    private let store: IngestionStore
    public var currency: CurrencyCode
    public private(set) var snapshot: ProvenanceSnapshot?
    public private(set) var loadFailed = false

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store; self.currency = currency
    }

    public func load() async {
        do { snapshot = try await store.provenanceSnapshot(displayCurrency: currency); loadFailed = false }
        catch { loadFailed = true }
    }

    public func addIncome(amount: Decimal, currency: CurrencyCode, sourceName: String) async {
        let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount > 0, !name.isEmpty else { return }
        try? await store.logIncome(amount: amount, currency: currency, sourceName: name)
        await load()
    }

    /// Fraction remaining (0...1) for the draining bar.
    public func fraction(_ b: SourceBalance) -> Double {
        guard b.totalInflow > 0 else { return 0 }
        let r = (b.remaining as NSDecimalNumber).doubleValue / (b.totalInflow as NSDecimalNumber).doubleValue
        return min(max(r, 0), 1)
    }

    public func remainingText(_ b: SourceBalance) -> String {
        Money(amount: b.remaining, currency: CurrencyCode(b.currencyCode)).formatted()
    }
    public func unaccountedText() -> String? {
        guard let s = snapshot, s.unaccounted > 0 else { return nil }
        return Money(amount: s.unaccounted, currency: CurrencyCode(s.displayCurrencyCode)).formatted()
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'SourcesModelTests'`
Expected: PASS.

- [ ] **Step 5: Implement the views** — create `Sources/GoldengoFeatures/Provenance/AddIncomeView.swift`:

```swift
import SwiftUI
import GoldengoDesignSystem
import GoldengoCore

/// Minimal income capture: amount, currency, source name (with suggestions), date.
public struct AddIncomeView: View {
    @State private var model: SourcesModel
    let existingSources: [String]
    let onDone: () -> Void
    @State private var amountString = ""
    @State private var sourceName = ""
    @State private var currency: CurrencyCode
    @State private var date = Date.now
    @FocusState private var amountFocused: Bool

    public init(model: SourcesModel, existingSources: [String], currency: CurrencyCode, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.existingSources = existingSources
        _currency = State(initialValue: currency)
        self.onDone = onDone
    }

    private var amount: Decimal { Decimal(string: amountString) ?? 0 }
    private var canSave: Bool { amount > 0 && !sourceName.trimmingCharacters(in: .whitespaces).isEmpty }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("0", text: $amountString)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                        .focused($amountFocused)
                        .font(.title2.weight(.semibold))
                }
                Section("From") {
                    TextField("Source (e.g. Sister, Freelance)", text: $sourceName)
                    if !existingSources.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: GoldengoTheme.Spacing.s) {
                                ForEach(existingSources, id: \.self) { s in
                                    Button(s) { sourceName = s }
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, GoldengoTheme.Spacing.m).padding(.vertical, 6)
                                        .background(Color.goldengoSurface).clipShape(Capsule())
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Add income")
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .contentShape(Rectangle())
            .onTapGesture { amountFocused = false }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        amountFocused = false
                        Task { await model.addIncome(amount: amount, currency: currency, sourceName: sourceName); onDone() }
                    }.disabled(!canSave)
                }
            }
        }
    }
}
```

- [ ] **Step 6: Implement `SourcesView`** — `Sources/GoldengoFeatures/Provenance/SourcesView.swift`:

```swift
import SwiftUI
import GoldengoDesignSystem
import GoldengoCore

/// Each named source as a draining pool, plus an Unaccounted row and an "Add income" entry.
public struct SourcesView: View {
    @State private var model: SourcesModel
    @State private var showAddIncome = false
    public init(model: SourcesModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(model.snapshot?.sources ?? []) { b in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(b.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(model.remainingText(b)).font(.subheadline.weight(.medium))
                        }
                        ProgressView(value: model.fraction(b))
                            .tint(GoldengoTheme.accent)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }
                if let unaccounted = model.unaccountedText() {
                    HStack {
                        Label("Unaccounted", systemImage: "questionmark.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(unaccounted).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.goldengoBackground.ignoresSafeArea())
            .navigationTitle("Sources")
            .overlay {
                if (model.snapshot?.sources.isEmpty ?? true) && model.unaccountedText() == nil {
                    ContentUnavailableView("No sources yet",
                        systemImage: "tray", description: Text("Add where your money came from — a remittance, a cash withdrawal, your pay."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddIncome = true } label: { Label("Add income", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showAddIncome, onDismiss: { Task { await model.load() } }) {
                AddIncomeView(model: model,
                              existingSources: (model.snapshot?.sources ?? []).map(\.name),
                              currency: model.currency, onDone: { showAddIncome = false })
            }
            .task { await model.load() }
        }
    }
}
```

- [ ] **Step 7: Build for the simulator**

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add Sources/GoldengoFeatures/Provenance/ Tests/GoldengoFeaturesTests/SourcesModelTests.swift
git commit -m "feat(gol-81): Sources screen (draining pools + Unaccounted) + income capture"
```

---

## Task 6: Add the Sources tab to RootView

**Files:** Modify `Sources/GoldengoFeatures/RootView.swift`.

- [ ] **Step 1: Own a SourcesModel** — add next to the other `@State` models in `RootView`:

```swift
    @State private var sourcesModel: SourcesModel
```

And in `init(store:)`, after `_quickAddModel = ...`:

```swift
        _sourcesModel = State(initialValue: SourcesModel(store: store, currency: preferred))
```

- [ ] **Step 2: Add the tab** — in the `TabView`, after the `SubscriptionsView` tab (tag 4), add:

```swift
            SourcesView(model: sourcesModel)
                .tabItem { Label("Sources", systemImage: "circle.grid.2x2") }
                .tag(5)
```

- [ ] **Step 3: Reload on entry** — in the `.onChange(of: selectedTab)` handler, add a branch:

```swift
            if newTab == 5 { Task { await sourcesModel.load() } }
```

- [ ] **Step 4: Build for the simulator**

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/RootView.swift
git commit -m "feat(gol-81): add Sources tab to RootView"
```

---

## Task 7: Full suite, device verification, ticket

- [ ] **Step 1: Full test suite** — `swift test` → all green (existing ~229 + new ProvenanceAllocator/ProvenanceStore/SourcesModel tests). Run the FULL suite (a `--filter` run hides cross-suite regressions — the GOL-79 lesson). Fix anything red before proceeding.

- [ ] **Step 2: Device build + install**

```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath AppProject/.build-device build
xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E AppProject/.build-device/Build/Products/Debug-iphoneos/Goldengo.app
```

- [ ] **Step 3: Manual device verification** — Sources tab present; "Add income" → "€200 from Sister" creates a source; log a few expenses → Sister's bar drains, each expense shows "funded by Sister"; spend beyond logged income → an Unaccounted row appears; an ALL expense against a EUR-only source draws EUR (cross-currency); the **CloudKit migration is non-destructive** (existing expenses survive the schema change — verify the app launches with prior data intact).

- [ ] **Step 4: Ticket** — set GOL-81 → To Verify with a summary comment (what shipped, test counts, the device checklist).

- [ ] **Step 5: Finish the branch** — second-Opus review over the diff → ff-merge to `main` → push.

---

## Self-Review

**Spec coverage:** SourceRecord + provenanceSource + schema (Task 1) ✓; pure FIFO allocator incl. cross-currency, overspend→Unaccounted, no-retroactive-funding (Task 2) ✓; logIncome/find-or-create/provenanceSnapshot + computed-not-stored (Task 3) ✓; "funded by" on Recent (Tasks 3+4) ✓; Sources screen with draining bars + Unaccounted + income capture (Task 5) ✓; new tab (Task 6) ✓; AccountRecord not reused (a new model is used) ✓; Decimal never in #Predicate (all allocator math in plain Swift; predicates filter only isArchived/kindRaw) ✓; additive migration verified on device (Task 7 step 3) ✓. Out-of-scope items (override, imported-income folding, animated hero, per-source budgets, transfers) are absent by construction.

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** `SourceRecord(id:name:currencyCode:colorIndex:…)`, `ExpenseRecord.provenanceSource`, `ProvenanceAllocator.Inflow/Outflow/FundingSegment/Allocation`, `IngestionStore.logIncome(amount:currency:sourceName:date:)`/`findOrCreateSource(named:currency:)`/`provenanceSnapshot(displayCurrency:rates:)`/`fundingLabels(displayCurrency:)`/`compute(rates:displayCurrency:)`, `SourceBalance`/`ProvenanceSnapshot`, `ExpenseSnapshot.fundedBy`, `SourcesModel(store:currency:)`/`.load()`/`.addIncome(amount:currency:sourceName:)`/`.fraction(_:)`/`.remainingText(_:)`/`.unaccountedText()`, `SourcesView(model:)`, `AddIncomeView(model:existingSources:currency:onDone:)` — all consistent across tasks. `.eur` is used in tests (confirmed available); `RateTable(base:rates:asOf:)` matches existing usage.
