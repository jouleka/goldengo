# GOL-68 Mixed-Currency Totals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Home + widget totals sum mixed-currency expenses by converting each to the display (preferred) currency via the GOL-67 rate table, with a tappable currency control on the dashboard and a subtle staleness caption.

**Architecture:** A pure `CurrencyConverter.sum([Money], to:)` (Core) does the converting sum. `IngestionStore`'s `todayTotal`/`dashboardSummary` take a `RateTable` and convert every expense (no more single-currency filtering); `DashboardSummary` gains `ratesAsOf`. The widget today-total is recomputed in the preferred currency. The dashboard total becomes a `Menu` that changes the default currency via a `RootView` callback. Recent rows are unchanged.

**Tech Stack:** Swift 6, SwiftData, SwiftUI (`Menu`/`.sheet`), XCTest. Reuses `CurrencyConverter`/`RateTable`/`SeedRates`/`ExchangeRateCache` (GOL-67) and `CurrencyPickerView`/`CurrencyCatalog` (GOL-66). No new deps; no `project.rb` change.

**Spec:** [docs/superpowers/specs/2026-06-03-gol68-mixed-currency-totals-design.md](../specs/2026-06-03-gol68-mixed-currency-totals-design.md)

**CI note:** GoldengoFeatures compiles on macOS; `Menu`/`.sheet`/`NavigationStack` are cross-platform.

---

## File Structure

**Modify (GoldengoCore):**
- `Sources/GoldengoCore/CurrencyConverter.swift` — add `sum(_:to:)`.

**Modify (GoldengoData):**
- `Sources/GoldengoData/IngestionStore+Dashboard.swift` — `DashboardSummary.ratesAsOf`; `dashboardSummary` converts.
- `Sources/GoldengoData/IngestionStore.swift` — `todayTotal(in:rates:)` converts; `refreshSharedTodayTotal()` helper replaces the two hardcoded-lek widget writes.
- `Sources/GoldengoData/RecentExpensesReading.swift` — add `rates:` to the two read methods.

**Modify (GoldengoFeatures):**
- `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift` — load the rate table, pass it; expose `ratesAsOf`.
- `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift` — currency `Menu` on the total + staleness caption + `onChangeCurrency`.
- `Sources/GoldengoFeatures/RootView.swift` — implement `onChangeCurrency` (set preferred + update both models + reload).

**Modify (tests):**
- `Tests/GoldengoCoreTests/CurrencyConverterTests.swift` — `sum` cases.
- `Tests/GoldengoDataTests/DashboardSummaryTests.swift` — pass `rates:`; add mixed-currency conversion test.
- `Tests/GoldengoDataTests/ReadMethodsTests.swift` — pass `rates:`; rewrite the filter test to a conversion test.
- `Tests/GoldengoDataTests/IngestionStoreTests.swift` — rewrite the "EUR doesn't inflate" test to conversion.
- `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift` — update the `FailingReader` fake signatures.

---

## Task 1: `CurrencyConverter.sum(_:to:)`

**Files:**
- Modify: `Sources/GoldengoCore/CurrencyConverter.swift`
- Test: `Tests/GoldengoCoreTests/CurrencyConverterTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/GoldengoCoreTests/CurrencyConverterTests.swift`, add inside the class (it already has the
`table(asOf:)` helper: USD base, `ALL:100`, `EUR:0.9`):

```swift
    // Totals add up across currencies: each Money is converted to the target, then summed.
    func test_sum_convertsEachAndAdds() {
        let c = CurrencyConverter(table: table())          // 1 USD = 100 ALL = 0.9 EUR
        let monies = [Money(amount: 100, currency: .all),  // 100 ALL = 0.9 EUR
                      Money(amount: Decimal(string: "0.9")!, currency: .eur)] // 0.9 EUR
        XCTAssertEqual(c.sum(monies, to: .eur), Decimal(string: "1.8")!)
    }

    // Same-currency-only sums are exact (identity, no rate needed).
    func test_sum_singleCurrency_isExact() {
        let c = CurrencyConverter(table: table())
        XCTAssertEqual(c.sum([Money(amount: 250, currency: .all), Money(amount: 750, currency: .all)], to: .all), 1000)
    }

    // An un-convertible entry (no rate) is skipped; the rest still count.
    func test_sum_skipsUnconvertible() {
        let c = CurrencyConverter(table: table())
        let monies = [Money(amount: 100, currency: .all), Money(amount: 5, currency: CurrencyCode("XYZ"))]
        XCTAssertEqual(c.sum(monies, to: .all), 100)       // XYZ has no rate → skipped
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CurrencyConverterTests`
Expected: FAIL — `sum` does not exist.

- [ ] **Step 3: Add `sum` to `CurrencyConverter`**

In `Sources/GoldengoCore/CurrencyConverter.swift`, add this method (after `convert(_ money:to:)`):

```swift
    /// Convert each `Money` to `target` and sum, skipping any that can't convert (missing rate).
    public func sum(_ monies: [Money], to target: CurrencyCode) -> Decimal {
        monies.reduce(Decimal(0)) { acc, m in
            (try? convert(m, to: target)).map { acc + $0.amount } ?? acc
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CurrencyConverterTests`
Expected: PASS (existing 6 + new 3)

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/CurrencyConverter.swift Tests/GoldengoCoreTests/CurrencyConverterTests.swift
git commit -m "feat(core): CurrencyConverter.sum converts a list of Money and adds"
```

---

## Task 2: Aggregation converts to the display currency

This is one atomic change: the read-method signatures gain `rates:`, the impls convert, `DashboardSummary`
gains `ratesAsOf`, and every caller/fake/test updates together so the build stays green.

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore+Dashboard.swift`
- Modify: `Sources/GoldengoData/IngestionStore.swift`
- Modify: `Sources/GoldengoData/RecentExpensesReading.swift`
- Modify: `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift`
- Test: `Tests/GoldengoDataTests/DashboardSummaryTests.swift`, `Tests/GoldengoDataTests/ReadMethodsTests.swift`, `Tests/GoldengoDataTests/IngestionStoreTests.swift`, `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift`

- [ ] **Step 1: Write the failing conversion test (DashboardSummaryTests)**

In `Tests/GoldengoDataTests/DashboardSummaryTests.swift`, add a shared rate table helper inside the
class and a new test. The helper: USD base, `1 USD = 100 ALL = 1 EUR` (so `1 EUR = 100 ALL`):

```swift
    private let rates = RateTable(base: CurrencyCode("USD"),
                                  rates: ["USD": 1, "ALL": 100, "EUR": 1],
                                  asOf: Date(timeIntervalSince1970: 1_780_444_800))

    func test_monthTotal_convertsMixedCurrenciesToDisplayCurrency() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        try await store.logManual(amount: 100, currency: .all, merchant: "Lek buy", categoryName: nil)   // 100 ALL
        try await store.logManual(amount: 2, currency: .eur, merchant: "Euro buy", categoryName: nil)     // 2 EUR = 200 ALL
        let inLek = try await store.dashboardSummary(in: .all, rates: rates, now: now)
        XCTAssertEqual(inLek.monthTotal, 300)            // 100 + 200
        XCTAssertEqual(inLek.ratesAsOf, rates.asOf)       // conversion happened → staleness date present
        let inEur = try await store.dashboardSummary(in: .eur, rates: rates, now: now)
        XCTAssertEqual(inEur.monthTotal, 3)              // 1 (100 ALL) + 2 EUR
    }

    func test_ratesAsOf_isNil_whenNoConversionNeeded() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        try await store.logManual(amount: 100, currency: .all, merchant: "Lek", categoryName: nil)
        let s = try await store.dashboardSummary(in: .all, rates: rates, now: now)
        XCTAssertNil(s.ratesAsOf)                         // all expenses already in display currency
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter DashboardSummaryTests`
Expected: FAIL — `dashboardSummary` has no `rates:` param and `DashboardSummary` has no `ratesAsOf`.

- [ ] **Step 3: Add `ratesAsOf` + convert in `dashboardSummary`**

Replace the whole body of `Sources/GoldengoData/IngestionStore+Dashboard.swift` with:

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

/// `Sendable` snapshot backing the Home dashboard. Totals are expressed in `currencyCode`, with
/// every expense converted into it via the supplied rate table.
public struct DashboardSummary: Sendable, Equatable {
    public var monthTotal: Decimal
    public var topCategories: [CategoryTotal]
    public var confirmedSubscriptionCount: Int
    public var confirmedSubscriptionsMonthly: Decimal   // monthly-equivalent sum
    public var currencyCode: String
    public var ratesAsOf: Date?                          // the rate date, when any conversion happened
    public init(monthTotal: Decimal, topCategories: [CategoryTotal], confirmedSubscriptionCount: Int,
                confirmedSubscriptionsMonthly: Decimal, currencyCode: String, ratesAsOf: Date?) {
        self.monthTotal = monthTotal; self.topCategories = topCategories
        self.confirmedSubscriptionCount = confirmedSubscriptionCount
        self.confirmedSubscriptionsMonthly = confirmedSubscriptionsMonthly
        self.currencyCode = currencyCode; self.ratesAsOf = ratesAsOf
    }
}

extension IngestionStore {
    /// Aggregates the current month's spend, top categories, and confirmed-subscription monthly
    /// equivalent — converting every expense into `displayCurrency` via `rates`.
    public func dashboardSummary(in displayCurrency: CurrencyCode = .all, rates: RateTable,
                                 now: Date = .now, topCategoryLimit: Int = 4) throws -> DashboardSummary {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
        let expenseRaw = TransactionKind.expense.rawValue
        let converter = CurrencyConverter(table: rates)
        let display = displayCurrency.rawValue

        let monthFd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw && $0.date >= monthStart
        })
        let monthRecords = try modelContext.fetch(monthFd)

        var monthTotal = Decimal(0)
        var byCategory: [String: Decimal] = [:]
        var usedConversion = false
        for r in monthRecords {
            if r.currencyCode != display { usedConversion = true }
            let v = (try? converter.convert(r.amount, from: CurrencyCode(r.currencyCode), to: displayCurrency)) ?? 0
            monthTotal += v
            byCategory[r.category?.name ?? "Uncategorized", default: 0] += v
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

- [ ] **Step 4: Convert in `todayTotal` + add the widget helper (IngestionStore.swift)**

In `Sources/GoldengoData/IngestionStore.swift`, replace `todayTotal` (lines 76–88) with:

```swift
    /// Sum of today's expense-kind amounts, each converted into `displayCurrency` via `rates`.
    public func todayTotal(in displayCurrency: CurrencyCode = .all, rates: RateTable) throws -> Decimal {
        let start = Calendar.current.startOfDay(for: .now)
        let expenseRaw = TransactionKind.expense.rawValue
        let fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw && $0.date >= start
        })
        let monies = try modelContext.fetch(fd).map {
            Money(amount: $0.amount, currency: CurrencyCode($0.currencyCode))
        }
        return CurrencyConverter(table: rates).sum(monies, to: displayCurrency)
    }

    /// Recompute the widget's today-total in the user's preferred currency and publish it.
    private func refreshSharedTodayTotal() throws {
        let display = SharedSummary().readPreferredCurrency()
        let rates = ExchangeRateCache().load() ?? SeedRates.table
        let total = try todayTotal(in: display, rates: rates)
        SharedSummary().writeTodayTotal(Money(amount: total, currency: display).formatted())
    }
```

Then replace the two widget-write blocks. At `logManual` (currently lines 125–126):

```swift
        let total = try todayTotal(in: .all)
        SharedSummary().writeTodayTotal(Money(amount: total, currency: .all).formatted())
```

becomes:

```swift
        try refreshSharedTodayTotal()
```

And identically at `importStatement` (currently lines 158–159), replace the same two lines with:

```swift
        try refreshSharedTodayTotal()
```

- [ ] **Step 5: Add `rates:` to the reader protocol**

In `Sources/GoldengoData/RecentExpensesReading.swift`, replace the two method declarations:

```swift
    func todayTotal(in currency: CurrencyCode) async throws -> Decimal
    func dashboardSummary(in currency: CurrencyCode, now: Date, topCategoryLimit: Int) async throws -> DashboardSummary
```

with:

```swift
    func todayTotal(in currency: CurrencyCode, rates: RateTable) async throws -> Decimal
    func dashboardSummary(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> DashboardSummary
```

- [ ] **Step 6: Update `RecentExpensesModel.load` + expose `ratesAsOf`**

In `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift`, replace `load()` (lines 22–34) with:

```swift
    public func load() async {
        do {
            let rates = ExchangeRateCache().load() ?? SeedRates.table
            let fetched = try await reader.recentExpenses(limit: 50)
            let total = try await reader.todayTotal(in: currency, rates: rates)
            rows = fetched
            todayTotalText = Money(amount: total, currency: currency).formatted()
            summary = try await reader.dashboardSummary(in: currency, rates: rates, now: .now, topCategoryLimit: 4)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// The rate date behind the converted totals, when conversion was involved (for the staleness caption).
    public var ratesAsOf: Date? { summary?.ratesAsOf }
```

- [ ] **Step 7: Update the `FailingReader` fake**

In `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift`, replace the fake's two methods (lines 32–33):

```swift
    func todayTotal(in currency: CurrencyCode) async throws -> Decimal { throw Boom() }
    func dashboardSummary(in currency: CurrencyCode, now: Date, topCategoryLimit: Int) async throws -> DashboardSummary { throw Boom() }
```

with:

```swift
    func todayTotal(in currency: CurrencyCode, rates: RateTable) async throws -> Decimal { throw Boom() }
    func dashboardSummary(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> DashboardSummary { throw Boom() }
```

- [ ] **Step 8: Update existing single-currency Data tests to pass `rates:`**

In `Tests/GoldengoDataTests/DashboardSummaryTests.swift`, the existing calls become (identity conversion
for all-lek data, so assertions are unchanged):
- line 22 `store.dashboardSummary(now: now)` → `store.dashboardSummary(rates: rates, now: now)`
- line 32 `store.dashboardSummary(now: now)` → `store.dashboardSummary(rates: rates, now: now)`
- line 45 `store.dashboardSummary(in: .all, now: now)` → `store.dashboardSummary(in: .all, rates: rates, now: now)`
- line 59 `store.dashboardSummary(now: now)` → `store.dashboardSummary(rates: rates, now: now)`

In `Tests/GoldengoDataTests/ReadMethodsTests.swift`, add a shared table at the top of the class and
update the identity calls:

```swift
    private let rates = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1],
                                  asOf: Date(timeIntervalSince1970: 1_780_444_800))
```
- line 20 `store.todayTotal()` → `store.todayTotal(rates: rates)`  (still 350)
- line 50 `store.todayTotal()` → `store.todayTotal(rates: rates)`  (still 100)

Then **replace** `test_todayTotal_filtersToRequestedCurrency` (lines 54–66) with a conversion test:

```swift
    func test_todayTotal_convertsAllExpensesToRequestedCurrency() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        let today = Date.now
        ctx.insert(ExpenseRecord(amount: 100, currencyCode: "ALL", date: today, kind: .expense, source: .manual, dedupeKey: "x"))
        ctx.insert(ExpenseRecord(amount: 50, currencyCode: "EUR", date: today, kind: .expense, source: .manual, dedupeKey: "y"))
        try ctx.save()
        let store = IngestionStore(modelContainer: container)
        // 1 EUR = 100 ALL. In lek: 100 + 50*100 = 5100. In euro: 100/100 + 50 = 51.
        XCTAssertEqual(try await store.todayTotal(in: .all, rates: rates), 5100)
        XCTAssertEqual(try await store.todayTotal(in: .eur, rates: rates), 51)
    }
```

In `Tests/GoldengoDataTests/IngestionStoreTests.swift`, **replace** `test_logManual_eurExpense_doesNotInflateAllTotal`
(lines 40–46) with a conversion test:

```swift
    // F2 — a EUR expense now converts INTO the lek total (was excluded under single-currency filtering).
    func test_logManual_eurExpense_convertsIntoLekTotal() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let rates = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1],
                              asOf: Date(timeIntervalSince1970: 1_780_444_800))
        try await store.logManual(amount: 1, currency: .eur, merchant: nil, categoryName: nil)
        let total = try await store.todayTotal(in: .all, rates: rates)   // 1 EUR = 100 ALL
        XCTAssertEqual(total, 100)
    }
```

- [ ] **Step 9: Run the full suite**

Run: `swift test`
Expected: PASS — every prior test plus the new conversion tests. (If a call site was missed, the compile
error names the file:line — add `rates:` there.)

- [ ] **Step 10: Commit**

```bash
git add Sources/GoldengoData/IngestionStore+Dashboard.swift Sources/GoldengoData/IngestionStore.swift \
        Sources/GoldengoData/RecentExpensesReading.swift Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift \
        Tests/GoldengoDataTests/DashboardSummaryTests.swift Tests/GoldengoDataTests/ReadMethodsTests.swift \
        Tests/GoldengoDataTests/IngestionStoreTests.swift Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift
git commit -m "feat(data): convert mixed-currency totals to the display currency"
```

---

## Task 3: Dashboard currency control + staleness caption

**Files:**
- Modify: `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`
- Modify: `Sources/GoldengoFeatures/RootView.swift`

UI — verified by build + runtime (Task 4). Follows the Quick Add menu idiom; reuses `CurrencyPickerView`.

- [ ] **Step 1: Add the `onChangeCurrency` callback + imports to `RecentExpensesView`**

In `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`, ensure the imports include
`import GoldengoCore` and `import GoldengoData` (add any missing). Add a stored callback property next
to the other `on…` closures and a sheet flag:

```swift
    let onChangeCurrency: (CurrencyCode) -> Void
    @State private var showCurrencyPicker = false
```

(Update the view's `init`/call site accordingly — see Step 4 for the RootView call site. If the view
uses a memberwise init, add `onChangeCurrency` as a parameter in the same position as the other
closures.)

- [ ] **Step 2: Make the month total a currency Menu + add the staleness caption**

In `monthCard`, replace the total `Text` (currently lines 183–186):

```swift
                    Text(model.monthTotalText())
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
```

with a tappable menu wrapping the total, plus the staleness caption under it:

```swift
                    Menu {
                        ForEach(menuCurrencies, id: \.rawValue) { c in
                            Button {
                                onChangeCurrency(c)
                            } label: {
                                if c.rawValue == model.currency.rawValue {
                                    Label(menuLabel(c), systemImage: "checkmark")
                                } else {
                                    Text(menuLabel(c))
                                }
                            }
                        }
                        Divider()
                        Button { showCurrencyPicker = true } label: {
                            Label("More currencies…", systemImage: "ellipsis.circle")
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(model.monthTotalText())
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    if let asOf = model.ratesAsOf {
                        Text("Rates as of \(asOf.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
```

- [ ] **Step 3: Add the menu helpers + the "More…" sheet to `RecentExpensesView`**

Add these helpers to the struct (e.g. near the cards section):

```swift
    private func menuLabel(_ c: CurrencyCode) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol)  \(name)"
    }
    private var availableCurrencies: [CurrencyCode] {
        CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
    }
    private var menuCurrencies: [CurrencyCode] {
        let have = Set(availableCurrencies.map(\.rawValue))
        var list = CurrencyCode.popular.filter { have.contains($0.rawValue) }
        if !list.contains(where: { $0.rawValue == model.currency.rawValue }) {
            list.insert(model.currency, at: 0)
        }
        return list
    }
```

Attach the sheet to the view's root (e.g. on the outermost `ScrollView`/`List` in `body`):

```swift
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencyPickerView(
                    available: availableCurrencies,
                    selectedCode: Binding(
                        get: { model.currency.rawValue },
                        set: { onChangeCurrency(CurrencyCode($0)) }
                    )
                )
            }
        }
```

- [ ] **Step 4: Implement `onChangeCurrency` in `RootView`**

In `Sources/GoldengoFeatures/RootView.swift`, at the `RecentExpensesView(...)` call site (currently
lines 44–50), add the callback:

```swift
            RecentExpensesView(
                model: recentModel,
                onAdd: { selectedTab = 0 },
                onOpenImport: { showImport = true },
                onOpenSettings: { showSettings = true },
                onOpenSubscriptions: { selectedTab = 4 },
                onChangeCurrency: { code in
                    SharedSummary().setPreferredCurrency(code)
                    quickAddModel.currency = code
                    recentModel.currency = code
                    Task { await recentModel.load() }
                }
            )
```

- [ ] **Step 5: Build the package + app**

Run: `swift build`
Expected: clean.

Run:
```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/GoldengoFeatures/Recent/RecentExpensesView.swift Sources/GoldengoFeatures/RootView.swift
git commit -m "feat(features): dashboard currency menu + staleness caption"
```

---

## Task 4: Runtime verification + review

**Files:** none (verification only).

- [ ] **Step 1: Seed mixed-currency data + screenshot the converted total**

```bash
APP="$(find AppProject/.build/Build/Products -name 'Goldengo.app' -path '*Debug-iphonesimulator*' | head -1)"
xcrun simctl boot "iPhone 17" 2>/dev/null || true
xcrun simctl install booted "$APP"
xcrun simctl spawn booted defaults write group.com.goldengo.app preferredCurrency -string ALL
SIMCTL_CHILD_GOLDENGO_SEED_SAMPLE=1 xcrun simctl launch booted com.goldengo.app
# add a euro + a usd expense via the UI is tap-driven; instead verify via the seeded lek data + the
# converted total being non-zero. Screenshot Home:
xcrun simctl openurl booted goldengo://home
xcrun simctl io booted screenshot /tmp/gol68-home.png
```
Confirm the "This month" total is **non-zero** in lek (the seeded data converts/sums), a `chevron.down`
shows on the total, and — if mixed-currency data is present — the "Rates as of …" caption appears.
Capture os_log:
```bash
xcrun simctl spawn booted log show --last 30s --predicate 'process == "Goldengo"' --style compact | grep -iE 'AttributeGraph|modifying state|cycle detected|hang|fatal'
```
Expected: empty.

- [ ] **Step 2: Device tap-test**

Build + install on the paired iPhone. Confirm: with lek + euro + USD expenses, the "This month" total
shows a correct single number in the default currency (not 0); tap it → menu → switch currency →
everything reconverts; the widget today-total reflects the default currency. (This is the user's
original bug — verify it's fixed end-to-end.)

- [ ] **Step 3: Second-Opus review**

Dispatch a general-purpose Opus 4.8 reviewer over `git diff main...HEAD` for GOL-68. Focus: conversion
correctness (Decimal, missing-rate skip, `ratesAsOf` set only on real conversion), the atomic
signature change (no missed caller), Sendable/`RateTable` across the actor boundary, no iOS-only API,
the `onChangeCurrency` flow updating both models, and that Recent rows still show per-currency. Fix
findings; re-run `swift test`.

- [ ] **Step 4: Final green gate**

Run: `swift test`
Expected: PASS. Branch ready to ff-merge to `main`.

---

## Self-Review

**1. Spec coverage:**
- `CurrencyConverter.sum` → Task 1. ✓
- Convert This-month / Today / Top-categories / subs-estimate via the rate table → Task 2 (`dashboardSummary`, `todayTotal`). ✓
- Widget total in the default currency (was hardcoded lek) → Task 2 (`refreshSharedTodayTotal`). ✓
- `DashboardSummary.ratesAsOf` + staleness caption → Task 2 (field) + Task 3 (caption). ✓
- Default currency changeable from the dashboard (menu) → Task 3 + RootView `onChangeCurrency`. ✓
- Recent rows unchanged → not touched (confirmed). ✓
- Tests: pure sum, mixed-currency aggregation, rewritten filter→convert tests, widget → Tasks 1–2; UI/runtime/device → Tasks 3–4. ✓
- Out of scope (subs tab GOL-69) → not touched. ✓

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N". Every edit shows full code; the only prose-guided step (RecentExpensesView init parameter in Step 1) is concrete (add `onChangeCurrency` in the same position, wired in Step 4's call site).

**3. Type consistency:** `CurrencyConverter.sum(_:to:)`, `todayTotal(in:rates:)`, `dashboardSummary(in:rates:now:topCategoryLimit:)`, `DashboardSummary(... ratesAsOf:)`, `RecentExpensesModel.ratesAsOf`, `onChangeCurrency: (CurrencyCode) -> Void`, `RateTable(base:rates:asOf:)`, `SeedRates.table`, `ExchangeRateCache().load()`, `CurrencyCatalog.selectable(from:)`, `CurrencyPickerView(available:selectedCode:)` — consistent across tasks and matching the GOL-66/67 signatures.
