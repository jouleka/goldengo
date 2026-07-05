# Spending by category + budgets — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A month-scoped "Spending by category" screen (donut + ranked rows) reached from Home, with a recurring monthly cap per category, live in-app amber/red progress, and an overspend push notification.

**Architecture:** Data layer (`GoldengoData`, the `IngestionStore` `@ModelActor`) owns all computation and the notify-once dedupe state — pure, testable, no `UserNotifications` import. Feature layer (`GoldengoFeatures`) owns the UI and *fires* the push, driven from the existing `RootView` scene-lifecycle hook. This split is forced by module layering: `GoldengoData` must not depend on `GoldengoFeatures`.

**Tech Stack:** Swift, SwiftUI, SwiftData (`@Model`, `@ModelActor`), Swift Charts (`SectorMark`, iOS 17+), `UserNotifications`, XCTest.

## Global Constraints

- **Never compare `Decimal` inside a SwiftData `#Predicate`** — it SIGSEGVs under load. Filter/aggregate `Decimal` in memory after a date-only fetch.
- **Run the full `swift test`** after each data-layer task — not a filtered subset (partial runs have masked the Decimal segfault before).
- **Keep `GoldengoDataTests` async-capable but do not link AppIntents** into any target that runs async tests (async XCTest under AppIntents is silently abandoned + corrupts the process).
- **Keyboard dismissal:** tap-outside / Return / after-action focus-clear. Never a keyboard "Done" toolbar.
- **UI matches on-`main` `GoldengoTheme`** (warm bone + gold) and reuses existing components (`goldengoCard()`, `GoldengoIconTile`, shared expense rows, `GoldengoCategoryIcon`). No serif — that was rejected on-device.
- **Copy is sentence case, no exclamation marks.**
- **Get it on the user's device early** as the go/no-go on the look — green tests are not sign-off.
- **Display currency** is whatever the existing dashboard entry uses; reuse that source, don't invent a new setting.
- **Commit after every green step.** Work on branch `feature/spending-by-category`.

---

## File Structure

**Create:**
- `Sources/GoldengoData/BudgetLevel.swift` — pure `BudgetLevel` enum + `forSpend(_:cap:)` threshold logic.
- `Sources/GoldengoData/IngestionStore+CategoryBreakdown.swift` — breakdown types + `categoryBreakdown(...)` and `evaluateBudgetAlerts(...)` actor methods.
- `Sources/GoldengoFeatures/Spending/CategoryBreakdownView.swift` — the screen.
- `Sources/GoldengoFeatures/Spending/CategoryBreakdownModel.swift` — its view model (loads breakdown, steps month, sets caps).
- `Sources/GoldengoFeatures/Spending/SpendingDonut.swift` — the Swift Charts donut.
- `Sources/GoldengoFeatures/Spending/CategoryDrilldownView.swift` — a category's month expenses; "Other" assign flow.
- `Sources/GoldengoFeatures/Spending/OverspendNotifications.swift` — the firing function (`"overspend:"` prefix, immediate trigger).
- `Tests/GoldengoDataTests/BudgetLevelTests.swift`
- `Tests/GoldengoDataTests/CategoryBreakdownTests.swift`
- `Tests/GoldengoDataTests/BudgetAlertTests.swift`

**Modify:**
- `Sources/GoldengoData/Models/CategoryRecord.swift` — add `monthlyBudget`, `budgetAlertLevelRaw`, `budgetAlertMonth`.
- `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift` — make the top-categories block tap → push the screen; over-dot.
- `Sources/GoldengoFeatures/RootView.swift` — `.task` + `.active` → evaluate + fire.
- `AppProject/Goldengo/GoldengoApp.swift` — register the overspend notification category + delegate branch.

---

## Task 1: Budget fields + threshold logic

**Files:**
- Modify: `Sources/GoldengoData/Models/CategoryRecord.swift`
- Create: `Sources/GoldengoData/BudgetLevel.swift`
- Test: `Tests/GoldengoDataTests/BudgetLevelTests.swift`

**Interfaces:**
- Produces: `BudgetLevel` (`.noBudget/.ok/.near/.over`, `String`-backed, `Sendable`), `BudgetLevel.forSpend(_ spent: Decimal, cap: Decimal?) -> BudgetLevel`, `BudgetLevel.rank: Int`; new `CategoryRecord` fields `monthlyBudget: Decimal?`, `budgetAlertLevelRaw: String`, `budgetAlertMonth: Date?`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import Foundation
@testable import GoldengoData

final class BudgetLevelTests: XCTestCase {
    func test_noBudget_whenCapNilOrZero() {
        XCTAssertEqual(BudgetLevel.forSpend(500, cap: nil), .noBudget)
        XCTAssertEqual(BudgetLevel.forSpend(500, cap: 0), .noBudget)
    }
    func test_ok_belowNearLine() {
        XCTAssertEqual(BudgetLevel.forSpend(0, cap: 100), .ok)
        XCTAssertEqual(BudgetLevel.forSpend(84, cap: 100), .ok)   // 84% < 85%
    }
    func test_near_atOrAbove85_below100() {
        XCTAssertEqual(BudgetLevel.forSpend(85, cap: 100), .near)  // exactly 85%
        XCTAssertEqual(BudgetLevel.forSpend(99, cap: 100), .near)
    }
    func test_over_atOrAbove100() {
        XCTAssertEqual(BudgetLevel.forSpend(100, cap: 100), .over) // exactly 100%
        XCTAssertEqual(BudgetLevel.forSpend(130, cap: 100), .over)
    }
    func test_rankOrders_okNearOver() {
        XCTAssertTrue(BudgetLevel.ok.rank < BudgetLevel.near.rank)
        XCTAssertTrue(BudgetLevel.near.rank < BudgetLevel.over.rank)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BudgetLevelTests`
Expected: FAIL — `BudgetLevel` undefined.

- [ ] **Step 3: Create `BudgetLevel.swift`**

```swift
import Foundation

/// How a category's month spend sits against its cap. All-Decimal comparison (in memory,
/// never inside a #Predicate) so the 85%/100% boundaries are exact — no float drift.
public enum BudgetLevel: String, Sendable, Equatable {
    case noBudget, ok, near, over

    /// The "close to your cap" line, as a fraction of the cap. Fixed in v1.
    public static let nearNumerator = Decimal(85)
    public static let nearDenominator = Decimal(100)

    public static func forSpend(_ spent: Decimal, cap: Decimal?) -> BudgetLevel {
        guard let cap, cap > 0 else { return .noBudget }
        if spent >= cap { return .over }
        if spent >= cap * nearNumerator / nearDenominator { return .near }
        return .ok
    }

    /// Escalation order for notify-once dedupe. noBudget/ok share 0 (no alert).
    public var rank: Int {
        switch self {
        case .noBudget, .ok: return 0
        case .near: return 1
        case .over: return 2
        }
    }
}
```

- [ ] **Step 4: Add fields to `CategoryRecord`**

In `Sources/GoldengoData/Models/CategoryRecord.swift`, add these stored properties alongside `colorHex` (all optional/defaulted → additive SwiftData migration, no migration plan needed):

```swift
    /// Recurring monthly cap in the user's display currency. nil = no cap.
    public var monthlyBudget: Decimal?
    /// Notify-once dedupe: the highest level we've PUSHED for `budgetAlertMonth`.
    public var budgetAlertLevelRaw: String = "none"
    /// The start-of-month `budgetAlertLevelRaw` applies to. nil = never pushed.
    public var budgetAlertMonth: Date?
```

Leave the existing `init` as-is (SwiftData populates the new optional/defaulted fields).

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter BudgetLevelTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Full test run (migration sanity)**

Run: `swift test`
Expected: PASS — existing tests still green with the new fields.

- [ ] **Step 7: Commit**

```bash
git add Sources/GoldengoData/BudgetLevel.swift Sources/GoldengoData/Models/CategoryRecord.swift Tests/GoldengoDataTests/BudgetLevelTests.swift
git commit -m "feat(budgets): CategoryRecord cap fields + BudgetLevel threshold logic"
```

---

## Task 2: Category breakdown aggregation

**Files:**
- Create: `Sources/GoldengoData/IngestionStore+CategoryBreakdown.swift`
- Test: `Tests/GoldengoDataTests/CategoryBreakdownTests.swift`

**Interfaces:**
- Consumes: `BudgetLevel.forSpend`, existing `CurrencyConverter`, the rate-loading used by the dashboard entry method.
- Produces: `CategoryBreakdownRow`, `CategoryBreakdown`, and `IngestionStore.categoryBreakdown(monthContaining:displayCurrency:rates:) async throws -> CategoryBreakdown` (rates caller-injected, matching `dashboardSummary`).

**Rate handling (resolved during execution):** `IngestionStore` never loads rates itself — every read method takes `rates: RateTable` from the caller (see `dashboardSummary(in:rates:now:)`, `homeData(in:rates:...)`). So `categoryBreakdown` takes a `rates: RateTable` parameter too. In tests, build the table exactly as `DashboardSummaryTests` does: `RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1], asOf: Date(timeIntervalSince1970: 1_780_444_800))`. Single-currency ALL test data → conversion is identity. Set `ratesAsOf` to `rates.asOf` only when a conversion actually happened (a record's currency ≠ display), else `nil` — same rule as the dashboard.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class CategoryBreakdownTests: XCTestCase {
    private func store() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }
    // Single-currency ALL data → conversion is identity. Rate table mirrors DashboardSummaryTests.
    private let rates = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1],
                                 asOf: Date(timeIntervalSince1970: 1_780_444_800))

    func test_groupsAndSumsByCategory_sortedDesc() async throws {
        let s = try store()
        _ = try await s.logManual(amount: 3000, currency: .all, merchant: nil, categoryName: "Food")
        _ = try await s.logManual(amount: 1000, currency: .all, merchant: nil, categoryName: "Food")
        _ = try await s.logManual(amount: 2000, currency: .all, merchant: nil, categoryName: "Coffee")
        let b = try await s.categoryBreakdown(monthContaining: .now, displayCurrency: .all, rates: rates)
        XCTAssertEqual(b.rows.map(\.name), ["Food", "Coffee"])   // 4000 before 2000
        XCTAssertEqual(b.rows.first?.spent, 4000)
        XCTAssertEqual(b.total, 6000)
    }

    func test_uncategorized_landsInOther() async throws {
        let s = try store()
        _ = try await s.logManual(amount: 500, currency: .all, merchant: "Kiosk", categoryName: nil)
        let b = try await s.categoryBreakdown(monthContaining: .now, displayCurrency: .all, rates: rates)
        XCTAssertEqual(b.rows.first?.name, "Other")
        XCTAssertEqual(b.rows.first?.spent, 500)
    }

    func test_share_isFractionOfTotal() async throws {
        let s = try store()
        _ = try await s.logManual(amount: 750, currency: .all, merchant: nil, categoryName: "Food")
        _ = try await s.logManual(amount: 250, currency: .all, merchant: nil, categoryName: "Coffee")
        let b = try await s.categoryBreakdown(monthContaining: .now, displayCurrency: .all, rates: rates)
        XCTAssertEqual(b.rows.first(where: { $0.name == "Food" })?.share ?? 0, 0.75, accuracy: 0.0001)
    }

    func test_levelReflectsCap() async throws {
        let s = try store()
        _ = try await s.logManual(amount: 900, currency: .all, merchant: nil, categoryName: "Food")
        try await s.setMonthlyBudget(categoryNamed: "Food", cap: 1000)   // 90% -> near
        let b = try await s.categoryBreakdown(monthContaining: .now, displayCurrency: .all, rates: rates)
        XCTAssertEqual(b.rows.first(where: { $0.name == "Food" })?.level, .near)
    }
}
```

> Note: if `logManual`'s label is different (confirm in `IngestionStore.swift`), adjust the calls. `setMonthlyBudget(categoryNamed:cap:)` is added in this task (Step 3).

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CategoryBreakdownTests`
Expected: FAIL — `categoryBreakdown`/`setMonthlyBudget` undefined.

- [ ] **Step 3: Implement the breakdown extension**

Create `Sources/GoldengoData/IngestionStore+CategoryBreakdown.swift`:

```swift
import Foundation
import SwiftData
import GoldengoCore

public struct CategoryBreakdownRow: Sendable, Equatable, Identifiable {
    public var name: String
    public var icon: String
    public var colorHex: String
    public var spent: Decimal
    public var budget: Decimal?
    public var share: Double
    public var level: BudgetLevel
    public var id: String { name }
}

public struct CategoryBreakdown: Sendable, Equatable {
    public var monthStart: Date
    public var total: Decimal
    public var rows: [CategoryBreakdownRow]
    public var currencyCode: String
    public var ratesAsOf: Date?
}

extension IngestionStore {
    /// Persist a cap on a category (creating it if missing). Used by the UI and tests.
    @discardableResult
    public func setMonthlyBudget(categoryNamed name: String, cap: Decimal?) throws -> Bool {
        let existing = try modelContext.fetch(FetchDescriptor<CategoryRecord>())
            .first { $0.name == name }
        let cat = existing ?? {
            let c = CategoryRecord(name: name); modelContext.insert(c); return c
        }()
        cat.monthlyBudget = cap
        try modelContext.save()
        return true
    }

    public func categoryBreakdown(monthContaining date: Date,
                                  displayCurrency: CurrencyCode,
                                  rates: RateTable) throws -> CategoryBreakdown {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? date

        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.date >= monthStart && $0.date < monthEnd })
        fd.relationshipKeyPathsForPrefetching = [\.category]
        let records = try modelContext.fetch(fd)

        let converter = CurrencyConverter(table: rates)
        let display = displayCurrency.rawValue
        let expenseRaw = TransactionKind.expense.rawValue

        var spentByName: [String: Decimal] = [:]
        var metaByName: [String: (icon: String, colorHex: String, budget: Decimal?)] = [:]
        var total = Decimal(0)
        var usedConversion = false
        for r in records where r.kindRaw == expenseRaw {
            if r.currencyCode != display { usedConversion = true }
            let key = r.category?.name ?? "Other"
            let v = (try? converter.convert(r.amount, from: CurrencyCode(r.currencyCode), to: displayCurrency)) ?? 0
            spentByName[key, default: 0] += v
            total += v
            if metaByName[key] == nil {
                metaByName[key] = (r.category?.icon ?? "tag",
                                   r.category?.colorHex ?? "#8C8373",
                                   r.category?.monthlyBudget)
            }
        }

        let totalDouble = (total as NSDecimalNumber).doubleValue
        let rows = spentByName.map { (name, spent) -> CategoryBreakdownRow in
            let m = metaByName[name] ?? ("tag", "#8C8373", nil)
            let share = totalDouble > 0 ? (spent as NSDecimalNumber).doubleValue / totalDouble : 0
            return CategoryBreakdownRow(name: name, icon: m.icon, colorHex: m.colorHex,
                                        spent: spent, budget: m.budget, share: share,
                                        level: BudgetLevel.forSpend(spent, cap: m.budget))
        }
        .sorted { $0.spent != $1.spent ? $0.spent > $1.spent : $0.name < $1.name }

        return CategoryBreakdown(monthStart: monthStart, total: total, rows: rows,
                                 currencyCode: display, ratesAsOf: usedConversion ? rates.asOf : nil)
    }
}
```

> Rates are the caller-injected `rates: RateTable` parameter — never load them inside `IngestionStore`. `ratesAsOf` is `rates.asOf` only when a conversion happened, else `nil` (matches `dashboardSummary`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CategoryBreakdownTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Full test run**

Run: `swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoData/IngestionStore+CategoryBreakdown.swift Tests/GoldengoDataTests/CategoryBreakdownTests.swift
git commit -m "feat(budgets): category breakdown aggregation with share + level"
```

---

## Task 3: Overspend alert evaluation + notify-once dedupe

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore+CategoryBreakdown.swift`
- Test: `Tests/GoldengoDataTests/BudgetAlertTests.swift`

**Interfaces:**
- Consumes: `BudgetLevel`, `setMonthlyBudget`, the rate loader.
- Produces: `BudgetAlert` (`categoryName`, `level`, `spent`, `budget`, `currencyCode`), and `IngestionStore.evaluateBudgetAlerts(asOf:displayCurrency:rates:) async throws -> [BudgetAlert]` (rates caller-injected).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class BudgetAlertTests: XCTestCase {
    private func store() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }
    // Single-currency ALL data → conversion is identity. Rate table mirrors DashboardSummaryTests.
    private let rates = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1],
                                 asOf: Date(timeIntervalSince1970: 1_780_444_800))

    func test_escalatesOnce_nearThenOver_thenSilent() async throws {
        let s = try store()
        try await s.setMonthlyBudget(categoryNamed: "Cigarettes", cap: 1000)

        _ = try await s.logManual(amount: 900, currency: .all, merchant: nil, categoryName: "Cigarettes")
        let near = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertEqual(near.map(\.level), [.near])

        let againSameLevel = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertTrue(againSameLevel.isEmpty)            // no re-fire at same level

        _ = try await s.logManual(amount: 300, currency: .all, merchant: nil, categoryName: "Cigarettes")
        let over = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertEqual(over.map(\.level), [.over])       // escalation near -> over fires once

        let silent = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertTrue(silent.isEmpty)
    }

    func test_noCap_neverAlerts() async throws {
        let s = try store()
        _ = try await s.logManual(amount: 9999, currency: .all, merchant: nil, categoryName: "Food")
        let alerts = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertTrue(alerts.isEmpty)
    }

    func test_newMonth_reArms() async throws {
        let s = try store()
        try await s.setMonthlyBudget(categoryNamed: "Food", cap: 1000)
        _ = try await s.logManual(amount: 1200, currency: .all, merchant: nil, categoryName: "Food")
        _ = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)   // fires over
        let cal = Calendar.current
        let nextMonth = cal.date(byAdding: .month, value: 1, to: .now)!
        // still over into the next month (recurring cap) -> re-arms and fires again once
        _ = try await s.logManual(amount: 1200, currency: .all, merchant: nil, categoryName: "Food", date: nextMonth)
        let next = try await s.evaluateBudgetAlerts(asOf: nextMonth, displayCurrency: .all, rates: rates)
        XCTAssertEqual(next.map(\.level), [.over])
    }
}
```

> Confirm `logManual` accepts a `date:` argument (the map shows `date: Date = .now`). If the label differs, adjust.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BudgetAlertTests`
Expected: FAIL — `evaluateBudgetAlerts` undefined.

- [ ] **Step 3: Implement evaluation**

Append to `IngestionStore+CategoryBreakdown.swift`:

```swift
public struct BudgetAlert: Sendable, Equatable {
    public var categoryName: String
    public var level: BudgetLevel      // .near or .over
    public var spent: Decimal
    public var budget: Decimal
    public var currencyCode: String
}

extension IngestionStore {
    public func evaluateBudgetAlerts(asOf now: Date = .now,
                                     displayCurrency: CurrencyCode,
                                     rates: RateTable) throws -> [BudgetAlert] {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        guard let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return [] }

        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.date >= monthStart && $0.date < monthEnd })
        fd.relationshipKeyPathsForPrefetching = [\.category]
        let records = try modelContext.fetch(fd)

        let converter = CurrencyConverter(table: rates)
        let expenseRaw = TransactionKind.expense.rawValue

        var spentByName: [String: Decimal] = [:]
        for r in records where r.kindRaw == expenseRaw {
            guard let name = r.category?.name else { continue }
            let v = (try? converter.convert(r.amount, from: CurrencyCode(r.currencyCode), to: displayCurrency)) ?? 0
            spentByName[name, default: 0] += v
        }

        // Categories with a cap — Decimal filtered in memory, never in a #Predicate.
        let capped = try modelContext.fetch(FetchDescriptor<CategoryRecord>()).filter { $0.monthlyBudget != nil }

        var alerts: [BudgetAlert] = []
        var mutated = false
        for cat in capped {
            guard let cap = cat.monthlyBudget else { continue }
            let spent = spentByName[cat.name] ?? 0
            let level = BudgetLevel.forSpend(spent, cap: cap)

            let sameMonth = cat.budgetAlertMonth.map {
                cal.isDate($0, equalTo: monthStart, toGranularity: .month)
            } ?? false
            let storedRank = sameMonth ? (BudgetLevel(rawValue: cat.budgetAlertLevelRaw)?.rank ?? 0) : 0

            if level.rank > storedRank {
                alerts.append(BudgetAlert(categoryName: cat.name, level: level, spent: spent,
                                          budget: cap, currencyCode: displayCurrency.rawValue))
                cat.budgetAlertLevelRaw = level.rawValue
                cat.budgetAlertMonth = monthStart
                mutated = true
            } else if !sameMonth {
                cat.budgetAlertLevelRaw = level.rawValue     // new-month baseline, no spurious alert
                cat.budgetAlertMonth = monthStart
                mutated = true
            }
        }
        if mutated { try modelContext.save() }
        return alerts
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BudgetAlertTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Full test run**

Run: `swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoData/IngestionStore+CategoryBreakdown.swift Tests/GoldengoDataTests/BudgetAlertTests.swift
git commit -m "feat(budgets): evaluateBudgetAlerts with notify-once dedupe"
```

---

## Task 4: Breakdown screen — month stepper, total, ranked rows

**Files:**
- Create: `Sources/GoldengoFeatures/Spending/CategoryBreakdownModel.swift`, `Sources/GoldengoFeatures/Spending/CategoryBreakdownView.swift`

**Interfaces:**
- Consumes: `IngestionStore.categoryBreakdown(monthContaining:displayCurrency:)`, `GoldengoTheme`, `goldengoCard()`, `Money`, `GoldengoCategoryIcon`.
- Produces: `CategoryBreakdownView(store:displayCurrency:)`.

**Before coding:** read `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift` and `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift` to copy: (a) how a model wraps `IngestionStore` and exposes `@Published`/`@Observable` snapshots, (b) the exact color/token accessors used for category dots and amounts, (c) how `Money(...)` is formatted in a row. Match those exactly.

- [ ] **Step 1: Build the model** — an `@Observable` (or `ObservableObject`, matching `RecentExpensesModel`) that holds `private(set) var breakdown: CategoryBreakdown?` and `private(set) var monthAnchor: Date = .now`, with:
  - `func load() async` → `breakdown = try? await store.categoryBreakdown(monthContaining: monthAnchor, displayCurrency: displayCurrency)`
  - `func step(_ delta: Int)` → advance `monthAnchor` by `delta` months (Calendar), then `await load()`
  - a `monthTitle: String` (e.g. "July 2026" via a cached `DateFormatter`).

- [ ] **Step 2: Build the view** — match the mockup structure:
  - Nav title "Spending".
  - Month stepper row: `‹` button (`step(-1)`), `monthTitle`, `›` button (`step(+1)`). Disable `›` when `monthAnchor` is the current month (no future).
  - Period total using `Money(amount: breakdown.total, currency: …).formatted()`.
  - `ForEach(breakdown.rows)` → a row: color dot from `colorHex`, `name`, right-aligned `Money(...).amountText()`, and `share` as a rounded `%`. (Progress bars come in Task 6.)
  - Wrap the rows list in `goldengoCard()`. Use `GoldengoTheme.Spacing` for gaps.
  - `.task { await model.load() }`.

- [ ] **Step 3: Add a temporary entry point to see it** — in `RecentExpensesView`, add a temporary `NavigationLink`/button to push `CategoryBreakdownView`. (Replaced properly in Task 9; this is only to verify on device now.)

- [ ] **Step 4: Build the app**

Run the project's app build (per the `run` skill / existing build command). Expected: compiles.

- [ ] **Step 5: On-device / simulator check** — launch, open the screen, confirm categories list with amounts + %, month stepper moves and reloads, current-month `›` is disabled. **Show the user a screenshot and get a look-check before proceeding.**

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoFeatures/Spending/CategoryBreakdownModel.swift Sources/GoldengoFeatures/Spending/CategoryBreakdownView.swift Sources/GoldengoFeatures/Recent/RecentExpensesView.swift
git commit -m "feat(spending): breakdown screen — month stepper, total, ranked rows"
```

---

## Task 5: Donut chart

**Files:**
- Create: `Sources/GoldengoFeatures/Spending/SpendingDonut.swift`
- Modify: `Sources/GoldengoFeatures/Spending/CategoryBreakdownView.swift`

**Interfaces:**
- Consumes: `CategoryBreakdown.rows`, Swift Charts.
- Produces: `SpendingDonut(rows:total:currencyCode:)`.

- [ ] **Step 1: Build the donut** using Swift Charts `SectorMark(angle: .value("spent", row.spent-as-Double), innerRadius: .ratio(0.62), angularInset: 1.5)`, `.foregroundStyle(Color(hex: row.colorHex))` (reuse the app's existing hex→Color initializer — find it in `GoldengoDesignSystem`; do not add a new one). Overlay the period total in the center via `.chartBackground` or a `ZStack`.

- [ ] **Step 2: Place it** above the rows card in `CategoryBreakdownView`, sized ~160pt. Hide it when `rows` is empty.

- [ ] **Step 3: Build + on-device check** — confirm segments match row colors and the center shows the total. Screenshot to the user.

- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoFeatures/Spending/SpendingDonut.swift Sources/GoldengoFeatures/Spending/CategoryBreakdownView.swift
git commit -m "feat(spending): donut with center total"
```

---

## Task 6: Budget progress bars + level tinting

**Files:**
- Modify: `Sources/GoldengoFeatures/Spending/CategoryBreakdownView.swift`

- [ ] **Step 1:** For each row where `budget != nil`, render under the name a thin progress bar: track = field color, fill width = `min(1, spent/budget)`, fill color by `level` — `ok` = income green, `near` = gold accent, `over` = terracotta danger (use the exact `GoldengoTheme` color accessors). Caption to the right: `ok`/`near` → "<remaining> left"; `over` → "over by <amount>" — using `Money(...).amountText()` for the numbers, tinted to match.

- [ ] **Step 2:** For the "Other" row (name == "Other"), instead of a bar show a gold "Tap to categorize this spend" affordance (wired in Task 8).

- [ ] **Step 3: Build + on-device check** — verify green/amber/red states with a capped category (set a cap via a temporary button or by seeding). Screenshot to the user.

- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoFeatures/Spending/CategoryBreakdownView.swift
git commit -m "feat(spending): per-category budget progress bars"
```

---

## Task 7: Set / edit a cap

**Files:**
- Modify: `Sources/GoldengoFeatures/Spending/CategoryBreakdownView.swift`, `CategoryBreakdownModel.swift`
- Modify: `Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift` (only to reuse `requestAuthorization()` — confirm exact type name)

**Interfaces:**
- Consumes: `IngestionStore.setMonthlyBudget(categoryNamed:cap:)`, the existing notification `requestAuthorization()`.

- [ ] **Step 1:** Add `func setCap(_ cap: Decimal?, for name: String) async` to the model → `try? await store.setMonthlyBudget(categoryNamed: name, cap: cap)` then `await load()`.

- [ ] **Step 2:** Tapping a category row's budget area (or a small "Set a cap" control when `budget == nil`) presents a minimal number entry (a `TextField` with `.keyboardType(.decimalPad)` inside a small sheet or inline editor). Parse to `Decimal`; empty clears the cap. **No keyboard "Done" toolbar** — dismiss via Return / tap-outside / clearing focus after submit.

- [ ] **Step 3:** On the **first** cap ever set (was `nil`, becomes non-nil), call the existing `requestAuthorization()` once. Confirm its exact type/namespace in `SubscriptionReminders.swift` before wiring.

- [ ] **Step 4: Build + on-device check** — set a cap, confirm the bar appears and permission is requested once; keyboard dismisses without a toolbar. Screenshot to the user.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/Spending/
git commit -m "feat(spending): set/edit monthly cap + request notification permission on first cap"
```

---

## Task 8: Drill-in + categorize from "Other"

**Files:**
- Create: `Sources/GoldengoFeatures/Spending/CategoryDrilldownView.swift`
- Modify: `Sources/GoldengoFeatures/Spending/CategoryBreakdownView.swift`

**Before coding:** find how the app currently lists a set of expenses as rows (the shared `homeRow`/`expenseHomeRow` in `Sources/GoldengoFeatures/Shared/ExpenseRowView.swift`) and how a category is assigned when logging (the QuickAdd category input). Reuse both.

- [ ] **Step 1:** Add `IngestionStore.expenses(inCategoryNamed:monthContaining:) async throws -> [ExpenseSnapshot]` in the data layer — date-only predicate for the month, then in memory keep `kind == .expense`, `!isArchived`, and either `category?.name == name` (normal categories) or, when `name == "Other"`, `category == nil || category?.name == "Other"`. Add a small test in `CategoryBreakdownTests` (Other bucket returns both nil-category and "Other"-named records). Run `swift test`.

- [ ] **Step 2:** `CategoryDrilldownView` lists those snapshots with the shared expense rows. Push it when a category row is tapped.

- [ ] **Step 3:** For "Other", each row gets an "assign category" affordance → the existing category picker/creator → `IngestionStore.assignCategory(named:toExpenseKey:)` (add this: look up the `ExpenseRecord` by `dedupeKey`, `findOrCreateCategory(named:)`, set relationship, save). Add a data-layer test: assigning moves an expense out of "Other". Run `swift test`.

- [ ] **Step 4: Build + on-device check** — tap a category → see its expenses; tap Other → reassign one → it leaves Other on reload. Screenshot to the user.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/IngestionStore+CategoryBreakdown.swift Sources/GoldengoFeatures/Spending/ Tests/GoldengoDataTests/CategoryBreakdownTests.swift
git commit -m "feat(spending): category drill-in + categorize from Other"
```

---

## Task 9: Home entry point + over-dot

**Files:**
- Modify: `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`

- [ ] **Step 1:** Replace the temporary entry (Task 4) with the real one: make the existing top-categories dashboard block a tap target that pushes `CategoryBreakdownView`. Match the existing navigation pattern used to push `HistoryView`.
- [ ] **Step 2:** When any capped category is `over` for the current month (derive from a lightweight `categoryBreakdown(monthContaining: .now)` the Home model already has, or reuse the dashboard summary), show a small terracotta dot on that block. No new persistent state.
- [ ] **Step 3: Build + on-device check** — tap the Home block → screen pushes; over-dot shows when a category is over. Screenshot to the user.
- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoFeatures/Recent/RecentExpensesView.swift
git commit -m "feat(spending): open breakdown from Home + over-budget dot"
```

---

## Task 10: Overspend notification firing

**Files:**
- Create: `Sources/GoldengoFeatures/Spending/OverspendNotifications.swift`
- Modify: `AppProject/Goldengo/GoldengoApp.swift`

**Before coding:** read the loan-nudge firing in `SubscriptionReminders.swift` and the delegate + `setNotificationCategories` block in `GoldengoApp.swift`. Match the identifier/prefix conventions and the delegate style.

- [ ] **Step 1:** Implement `enum OverspendNotifications` with `static let prefix = "overspend:"` and:

```swift
static func fire(_ alerts: [BudgetAlert]) async {
    #if canImport(UserNotifications)
    guard !isRunningTests else { return }
    let center = UNUserNotificationCenter.current()
    for a in alerts {
        let content = UNMutableNotificationContent()
        let spent = Money(amount: a.spent, currency: CurrencyCode(a.currencyCode)).formatted()
        let cap = Money(amount: a.budget, currency: CurrencyCode(a.currencyCode)).formatted()
        if a.level == .over {
            content.title = "Over budget on \(a.categoryName)"
            content.body = "You've spent \(spent) of your \(cap) cap this month."
        } else {
            content.title = "Close to your \(a.categoryName) cap"
            content.body = "\(spent) spent of \(cap) this month."
        }
        content.sound = .default
        content.categoryIdentifier = prefix
        let req = UNNotificationRequest(identifier: prefix + a.categoryName + ":" + a.level.rawValue,
                                        content: content, trigger: nil)  // nil = deliver now
        try? await center.add(req)
    }
    #endif
}
```

> Reuse the app's existing `isRunningTests` helper (same one `requestAuthorization()` uses). `trigger: nil` delivers immediately — deliberately different from the reminders' 09:00 calendar trigger.

- [ ] **Step 2:** In `GoldengoApp.swift`, register an overspend category in the existing `setNotificationCategories([...])` call: `UNNotificationCategory(identifier: OverspendNotifications.prefix, actions: [], intentIdentifiers: [])`. In the delegate's `didReceive`, add a branch: identifier `hasPrefix(OverspendNotifications.prefix)` → route to the Spending screen (or just complete). Keep `willPresent` returning `[.banner, .sound]`.

- [ ] **Step 3: Build** — compiles.
- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoFeatures/Spending/OverspendNotifications.swift AppProject/Goldengo/GoldengoApp.swift
git commit -m "feat(budgets): overspend local notification firing + category registration"
```

---

## Task 11: Wire evaluation into the app lifecycle

**Files:**
- Modify: `Sources/GoldengoFeatures/RootView.swift`

- [ ] **Step 1:** Add `private func checkOverspend()` that does `Task { let alerts = try? await store.evaluateBudgetAlerts(asOf: .now, displayCurrency: displayCurrency); if let alerts { await OverspendNotifications.fire(alerts) } }`. Use the same `store`/`displayCurrency` the surrounding code already has.
- [ ] **Step 2:** Call `checkOverspend()` in the existing `.task { … }` (cold launch) and in the `scenePhase == .active` branch of the existing `.onChange(of: scenePhase)` — right where `recentModel.load()`/`subsModel.load()` are called.
- [ ] **Step 3: On-device / simulator check (end-to-end):** set a cap, background the app, log an expense over the cap via the Quick-Log shortcut (or seed one dated now), foreground → a single overspend banner appears; foreground again → no duplicate. Screenshot/confirm to the user.
- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoFeatures/RootView.swift
git commit -m "feat(budgets): evaluate + fire overspend alerts on launch and foreground"
```

---

## Task 12: Full verification pass

- [ ] **Step 1:** `swift test` (full suite) — all green.
- [ ] **Step 2:** Build the app target; no warnings introduced in new files.
- [ ] **Step 3:** On-device walkthrough of the whole flow (Home block → breakdown → donut → set cap → drill-in → categorize Other → overspend banner). Get the user's on-device sign-off on the look (the go/no-go gate).
- [ ] **Step 4:** Use `superpowers:requesting-code-review` before merge.

---

## Self-Review (against the spec)

- **Breakdown (donut + ranked rows + share + total):** Tasks 2, 4, 5. ✓
- **Month stepper (this month + back/forward, no future):** Task 4. ✓
- **One recurring cap per category (`monthlyBudget`):** Task 1, 7. ✓
- **In-app amber/red progress + captions:** Task 6. ✓
- **Drill-in + categorize from Other (nil OR "Other" name):** Task 8. ✓
- **Home entry + over-dot:** Task 9. ✓
- **Overspend push, immediate trigger, reuse existing plumbing, permission on first cap:** Tasks 7, 10, 11. ✓
- **Detection in data / firing in features, driven by RootView lifecycle:** Tasks 3, 10, 11. ✓
- **Notify-once dedupe (escalate once per level/month, re-arm next month, monotonic):** Task 3. ✓
- **Exclusions (transfer/lent/income/archived), multi-currency, Decimal never in #Predicate:** Tasks 2, 3 (+ tests). ✓
- **Deferred (per-month overrides, rollover, closed-app detection):** not built. ✓
- **Open items to confirm during build:** exact rate accessor (Task 2), scheduler type name (Task 7), category-picker reuse (Task 8) — each has an explicit "before coding" read step.
