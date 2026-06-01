# Home / Dashboard Implementation Plan (GOL-8)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Turn the existing **Recent** tab into a **Home** dashboard: this-month spend total (headline), a confirmed-subscriptions summary card, top spend categories this month, and the recent-expenses list.

**Why enrich Recent (not a new tab):** the app already has 5 tabs (Add/Recent/Import/Subs/Settings); a 6th triggers iOS's "More" tab. The spec's "Home" explicitly includes the recent list, so Home = the Recent tab enriched with dashboard cards. Tab stays at tag 1; label/icon become "Home"/house.

**Architecture:** One new `@ModelActor` aggregation method `dashboardSummary(...)` returns a `Sendable DashboardSummary` (month total + top categories + confirmed-subscription monthly-equivalent). The Recent screen's model/view (which already use the `RecentExpensesReading` protocol seam + `loadFailed` from GOL-54) gain the summary; the view renders cards above the list.

**Branch:** `gol-8-dashboard`. **Commit rule:** NO `Co-Authored-By: Claude` trailer.

---

## File Structure
- **Create:** `Sources/GoldengoData/IngestionStore+Dashboard.swift` (`DashboardSummary`, `CategoryTotal`, `dashboardSummary`, `monthlyEquivalent`).
- **Create:** `Tests/GoldengoDataTests/DashboardSummaryTests.swift`.
- **Modify:** `Sources/GoldengoData/RecentExpensesReading.swift` (add `dashboardSummary` to the protocol).
- **Modify:** `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift` (load + expose `summary`).
- **Modify:** `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift` (cards above the list).
- **Modify:** `Sources/GoldengoFeatures/RootView.swift` (tab label "Home"/house; deep-link `home` alias).
- **Modify:** `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift` (FailingReader conforms to the new method; assert summary loads).

---

## Task 1: Store dashboard aggregation (`GoldengoData`)

**Files:** Create `Sources/GoldengoData/IngestionStore+Dashboard.swift`; Test `Tests/GoldengoDataTests/DashboardSummaryTests.swift`.

> Context: `ExpenseRecord` has `amount: Decimal`, `currencyCode`, `kindRaw`, `date`, `isArchived`, `category: CategoryRecord?`. `SubscriptionRecord` has `amount`, `currencyCode`, `cadence: SubscriptionCadence` (.weekly/.monthly/.quarterly/.yearly), `isConfirmed`/`isDismissed`/`isArchived`. Mirror `todayTotal`'s predicate style (hoist `expenseRaw`/`code` locals; `kindRaw == expenseRaw`).

- [ ] **Step 1: failing tests** — create `Tests/GoldengoDataTests/DashboardSummaryTests.swift`:

```swift
import XCTest
import GoldengoCore
@testable import GoldengoData

final class DashboardSummaryTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    private func ingest(_ store: IngestionStore, _ id: String, _ amount: Double, _ date: Date, merchant: String, kind: TransactionKind = .expense) async throws {
        _ = try await store.ingest(NormalizedTransaction(externalID: id, amount: Decimal(amount), currency: .all,
            date: date, rawMerchant: merchant, kind: kind, accountRef: "card"), source: .imported)
    }

    func test_monthTotal_countsOnlyCurrentMonthExpenses() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        try await ingest(store, "a", 1000, day(2026, 6, 2), merchant: "Spar")   // this month
        try await ingest(store, "b", 500, day(2026, 6, 10), merchant: "Conad")  // this month
        try await ingest(store, "c", 9999, day(2026, 5, 30), merchant: "Old")    // last month — excluded
        try await ingest(store, "d", 7777, day(2026, 6, 5), merchant: "Pay", kind: .income) // income — excluded
        let s = try await store.dashboardSummary(now: now)
        XCTAssertEqual(s.monthTotal, 1500)
    }

    func test_topCategories_sortedDescending() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        // No merchant→category mapping, so category is nil → "Uncategorized"; group by amount instead via 2 merchants.
        try await ingest(store, "a", 300, day(2026, 6, 2), merchant: "Coffee Corner")
        try await ingest(store, "b", 1200, day(2026, 6, 3), merchant: "Spar Market")
        let s = try await store.dashboardSummary(now: now)
        XCTAssertFalse(s.topCategories.isEmpty)
        // Sorted by total desc.
        XCTAssertEqual(s.topCategories, s.topCategories.sorted { $0.total >= $1.total })
        XCTAssertEqual(s.topCategories.reduce(Decimal(0)) { $0 + $1.total }, 1500)
    }

    func test_monthTotal_isCurrencyIsolated() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        try await ingest(store, "all1", 1000, day(2026, 6, 2), merchant: "Spar")            // ALL
        _ = try await store.ingest(NormalizedTransaction(externalID: "eur1", amount: 50, currency: CurrencyCode("EUR"),
            date: day(2026, 6, 3), rawMerchant: "Amazon", kind: .expense, accountRef: "card"), source: .imported) // EUR
        let s = try await store.dashboardSummary(in: .all, now: now)
        XCTAssertEqual(s.monthTotal, 1000)   // EUR charge excluded from the ALL total
        XCTAssertEqual(s.topCategories.reduce(Decimal(0)) { $0 + $1.total }, 1000)  // categories also currency-isolated
    }

    func test_confirmedSubscriptionsMonthlyEquivalent() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        // Build a confirmed monthly Netflix (1200) via detection + confirm.
        for m in [3, 4, 5] { try await ingest(store, "nf\(m)", 1200, day(2026, m, 5), merchant: "Netflix") }
        _ = try await store.refreshSubscriptions(now: day(2026, 5, 10))
        let key = try await XCTUnwrap(store.subscriptionCandidates().first?.id)
        try await store.confirmSubscription(matchKey: key)
        let s = try await store.dashboardSummary(now: now)
        XCTAssertEqual(s.confirmedSubscriptionCount, 1)
        XCTAssertEqual(s.confirmedSubscriptionsMonthly, 1200)   // monthly cadence → ×1
    }
}
```

- [ ] **Step 2: run → FAIL** (`dashboardSummary` undefined). `swift test --filter GoldengoDataTests.DashboardSummaryTests`

- [ ] **Step 3: implement** — create `Sources/GoldengoData/IngestionStore+Dashboard.swift`:

```swift
import Foundation
import SwiftData
import GoldengoCore

public struct CategoryTotal: Sendable, Equatable, Identifiable {
    public var name: String
    public var total: Decimal
    public var id: String { name }
    public init(name: String, total: Decimal) { self.name = name; self.total = total }
}

/// `Sendable` snapshot backing the Home dashboard. Single-currency by design (like `todayTotal`).
public struct DashboardSummary: Sendable, Equatable {
    public var monthTotal: Decimal
    public var topCategories: [CategoryTotal]
    public var confirmedSubscriptionCount: Int
    public var confirmedSubscriptionsMonthly: Decimal   // monthly-equivalent sum
    public var currencyCode: String
    public init(monthTotal: Decimal, topCategories: [CategoryTotal], confirmedSubscriptionCount: Int,
                confirmedSubscriptionsMonthly: Decimal, currencyCode: String) {
        self.monthTotal = monthTotal; self.topCategories = topCategories
        self.confirmedSubscriptionCount = confirmedSubscriptionCount
        self.confirmedSubscriptionsMonthly = confirmedSubscriptionsMonthly; self.currencyCode = currencyCode
    }
}

extension IngestionStore {
    /// Aggregates the current calendar month's expense spend, top categories, and the
    /// monthly-equivalent of confirmed subscriptions — all in ONE currency.
    public func dashboardSummary(in currency: CurrencyCode = .all, now: Date = .now,
                                 topCategoryLimit: Int = 4) throws -> DashboardSummary {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
        let expenseRaw = TransactionKind.expense.rawValue
        let code = currency.rawValue

        let monthFd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw && $0.date >= monthStart && $0.currencyCode == code
        })
        let monthRecords = try modelContext.fetch(monthFd)
        let monthTotal = monthRecords.reduce(Decimal(0)) { $0 + $1.amount }

        var byCategory: [String: Decimal] = [:]
        for r in monthRecords { byCategory[r.category?.name ?? "Uncategorized", default: 0] += r.amount }
        let topCategories = byCategory
            .map { CategoryTotal(name: $0.key, total: $0.value) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
            .prefix(topCategoryLimit).map { $0 }

        let confirmed = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>(predicate: #Predicate {
            $0.isConfirmed == true && $0.isDismissed == false && $0.isArchived == false && $0.currencyCode == code
        }))
        let subsMonthly = confirmed.reduce(Decimal(0)) { $0 + Self.monthlyEquivalent($1.amount, cadence: $1.cadence) }

        return DashboardSummary(monthTotal: monthTotal, topCategories: topCategories,
                                confirmedSubscriptionCount: confirmed.count,
                                confirmedSubscriptionsMonthly: subsMonthly, currencyCode: code)
    }

    /// Normalize a cadence amount to a per-month figure.
    static func monthlyEquivalent(_ amount: Decimal, cadence: SubscriptionCadence) -> Decimal {
        switch cadence {
        case .weekly:    return amount * Decimal(52) / Decimal(12)
        case .monthly:   return amount
        case .quarterly: return amount / Decimal(3)
        case .yearly:    return amount / Decimal(12)
        }
    }
}
```

- [ ] **Step 4: run → PASS**, then `swift test --filter GoldengoDataTests` (no regressions).

- [ ] **Step 5: commit** — `git add Sources/GoldengoData/IngestionStore+Dashboard.swift Tests/GoldengoDataTests/DashboardSummaryTests.swift` then `git commit -m "feat(GOL-8): dashboard aggregation — month total, top categories, confirmed-subscription monthly-equivalent"`

---

## Task 2: Home UI (`GoldengoFeatures`)

**Files:** modify `RecentExpensesReading.swift`, `RecentExpensesModel.swift`, `RecentExpensesView.swift`, `RootView.swift`, `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift`.

- [ ] **Step 1: extend the protocol** — in `Sources/GoldengoData/RecentExpensesReading.swift`, add to the protocol:
```swift
    func dashboardSummary(in currency: CurrencyCode, now: Date, topCategoryLimit: Int) async throws -> DashboardSummary
```
(`extension IngestionStore: RecentExpensesReading {}` already satisfies it via the Task 1 method's defaults.)

- [ ] **Step 2: model** — in `RecentExpensesModel.swift`, add `public private(set) var summary: DashboardSummary?` and load it inside the existing `do` block (before `loadFailed = false`):
```swift
            summary = try await reader.dashboardSummary(in: currency, now: .now, topCategoryLimit: 4)
```
Add these helpers:
```swift
    public func monthTotalText() -> String {
        Money(amount: summary?.monthTotal ?? 0, currency: currency).formatted()
    }
    public func subscriptionsText() -> String? {
        guard let s = summary, s.confirmedSubscriptionCount > 0 else { return nil }
        let monthly = Money(amount: s.confirmedSubscriptionsMonthly, currency: currency).formatted()
        return "\(s.confirmedSubscriptionCount) confirmed · ~\(monthly)/mo"
    }
```

- [ ] **Step 3: update the failing-reader test** — in `RecentExpensesModelTests.swift`, the `FailingReader` must implement the new method:
```swift
    func dashboardSummary(in currency: CurrencyCode, now: Date, topCategoryLimit: Int) async throws -> DashboardSummary { throw Boom() }
```
Add to `test_load_populatesRowsAndTodayTotal`: `XCTAssertNotNil(m.summary)`. The failure test already asserts `loadFailed`; also assert `m.summary == nil` after failure.

- [ ] **Step 4: view** — in `RecentExpensesView.swift`, ABOVE the existing `Section("Today")`, add (guarded on `model.summary`):
```swift
                if let s = model.summary {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("This month").font(.caption).foregroundStyle(.secondary)
                            Text(model.monthTotalText()).font(.largeTitle.bold())
                        }
                    }
                    if let subs = model.subscriptionsText() {
                        Section("Subscriptions") { Label(subs, systemImage: "repeat.circle") }
                    }
                    if !s.topCategories.isEmpty {
                        Section("Top categories this month") {
                            ForEach(s.topCategories) { c in
                                HStack { Text(c.name); Spacer()
                                    Text(Money(amount: c.total, currency: CurrencyCode(s.currencyCode)).formatted())
                                        .foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
```
Keep the existing "Today" + "Recent" sections below. (Requires `import GoldengoData` if not present — it is, transitively via the model; add `import GoldengoData` to be safe.)

- [ ] **Step 5a: RootView tab** — change the Recent tab's `.tabItem` (keep `.tag(1)`):
```swift
            RecentExpensesView(model: RecentExpensesModel(store: store))
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(1)
```
- [ ] **Step 5b: RootView deep link** — in `tab(forDeepLink:)`, add the `home` alias to the SWITCH. Replace:
```swift
        case "recent":        return 1
```
with:
```swift
        case "recent":        return 1
        case "home":          return 1
```
(Both `goldengo://recent` and `goldengo://home` now resolve to the Home tab.)

- [ ] **Step 6: build + tests** — `swift build`, then `swift test --filter GoldengoFeaturesTests`, then full `swift test`. All green.

- [ ] **Step 7: routing test** — in `RootViewRoutingTests.swift` add: `XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://home")!), 1)`.

- [ ] **Step 8: commit** — `git commit -m "feat(GOL-8): Home dashboard — month total, subscriptions card, top categories above recent list"`

---

## Final verification
- [ ] `swift test` all green; `swift build` clean.
- [ ] App + Simulator with `SIMCTL_CHILD_GOLDENGO_SEED_SAMPLE=1`: open Home → shows "This month", a subscriptions card (Netflix confirmed), top categories, and the recent list. (The seed also logs a current-month demo expense — see note.)
- [ ] No `Co-Authored-By` trailer.

> **Demo note:** the sample statement's charges are dated Mar–May; "this month" (the run date) would be 0. So ALSO update the DEBUG seed in `AppProject/Goldengo/GoldengoApp.swift` to log one current-dated expense after import, e.g. `try? await store.logManual(amount: 850, currency: .all, merchant: "Demo Lunch", categoryName: "Food")`, so Home's month total + categories are non-zero for screenshots.

## Spec Coverage (GOL-8)
- Month total (big number) ✅ · spend breakdown → top categories ✅ · recent expenses list ✅ (existing) · Subscriptions summary card ✅. Expense detail/edit screen is OUT OF SCOPE (separate story if wanted).
