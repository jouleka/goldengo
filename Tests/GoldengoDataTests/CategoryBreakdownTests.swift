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
        try await s.setMonthlyBudget(categoryNamed: "Food", cap: 1000, currency: .all)   // 90% -> near
        let b = try await s.categoryBreakdown(monthContaining: .now, displayCurrency: .all, rates: rates)
        XCTAssertEqual(b.rows.first(where: { $0.name == "Food" })?.level, .near)
    }

    func test_classifiesSubcategoriesAndSeparatesInvestmentFromSpending() async throws {
        let s = try store()
        _ = try await s.logManual(amount: 1_000, currency: .all, merchant: nil, categoryName: "Rent")
        _ = try await s.logManual(amount: 500, currency: .all, merchant: nil, categoryName: "Car maintenance")
        _ = try await s.logManual(amount: 2_000, currency: .all, merchant: nil, categoryName: "Stocks")
        _ = try await s.logManual(amount: 300, currency: .all, merchant: nil, categoryName: "Gambling")

        let b = try await s.categoryBreakdown(monthContaining: .now, displayCurrency: .all, rates: rates)

        XCTAssertEqual(b.total, 3_800, "all money out still drains the wallet")
        XCTAssertEqual(b.spendingTotal, 1_800, "investing is not ordinary consumption")
        XCTAssertEqual(b.investedTotal, 2_000)
        XCTAssertEqual(b.wasteTotal, 300)
        XCTAssertEqual(b.rows.first(where: { $0.name == "Rent" })?.groupName, "Housing")
        XCTAssertEqual(b.rows.first(where: { $0.name == "Car maintenance" })?.groupName, "Transport")
        XCTAssertEqual(b.rows.first(where: { $0.name == "Stocks" })?.purpose, .wealth)
    }

    func test_knownCategoriesReceiveDistinctTaxonomyColors() async throws {
        let s = try store()
        _ = try await s.logManual(amount: 100, currency: .all, merchant: nil, categoryName: "Rent")
        _ = try await s.logManual(amount: 100, currency: .all, merchant: nil, categoryName: "Stocks")
        _ = try await s.logManual(amount: 100, currency: .all, merchant: nil, categoryName: "Gambling")

        let rows = try await s.categoryBreakdown(monthContaining: .now, displayCurrency: .all, rates: rates).rows
        XCTAssertEqual(Set(rows.map(\.colorHex)).count, 3)
    }

    func test_investmentDoesNotExposeConsumptionBudget() async throws {
        let s = try store()
        try await s.setMonthlyBudget(categoryNamed: "Stocks", cap: 1_000, currency: .all)
        _ = try await s.logManual(amount: 1_200, currency: .all, merchant: nil, categoryName: "Stocks")

        let row = try await s.categoryBreakdown(monthContaining: .now, displayCurrency: .all, rates: rates).rows.first
        XCTAssertEqual(row?.purpose, .wealth)
        XCTAssertNil(row?.budget)
        XCTAssertEqual(row?.level, .noBudget)
        let alerts = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertTrue(alerts.isEmpty)
    }

    func test_cap_setWithDifferentCase_landsOnSameCategoryAsSpend() async throws {
        // A cap set as "food" and spend logged as "Food" must resolve to ONE CategoryRecord
        // (via findOrCreateCategory), so the cap can never orphan onto a cased duplicate.
        let s = try store()
        try await s.setMonthlyBudget(categoryNamed: "food", cap: 1000, currency: .all) // lowercase
        _ = try await s.logManual(amount: 900, currency: .all, merchant: nil, categoryName: "Food")  // capitalized
        let b = try await s.categoryBreakdown(monthContaining: .now, displayCurrency: .all, rates: rates)
        let foodRows = b.rows.filter { $0.name.caseInsensitiveCompare("food") == .orderedSame }
        XCTAssertEqual(foodRows.count, 1, "cap and spend must land on one category, not a cased duplicate")
        XCTAssertEqual(foodRows.first?.budget, 1000, "the cap must attach to the same record the spend grouped under")
        XCTAssertNotEqual(foodRows.first?.level, .noBudget)   // 900/1000 → capped, not uncapped
    }

    func test_capKeepsEntryCurrencyAndConvertsWhenDisplayCurrencyChanges() async throws {
        let s = try store()
        try await s.setMonthlyBudget(categoryNamed: "Food", cap: 10_000, currency: .all)
        _ = try await s.logManual(amount: 5_000, currency: .all, merchant: nil, categoryName: "Food")

        let eur = try await s.categoryBreakdown(monthContaining: .now,
                                                displayCurrency: .eur, rates: rates)
        let food = try XCTUnwrap(eur.rows.first(where: { $0.name == "Food" }))
        XCTAssertEqual(food.spent, 50)
        XCTAssertEqual(food.budget, 100)
        XCTAssertEqual(food.level, .ok)
    }

    func test_cappedCategoryAppearsBeforeAnySpending() async throws {
        let s = try store()
        try await s.setMonthlyBudget(categoryNamed: "Groceries", cap: 20_000, currency: .all)

        let breakdown = try await s.categoryBreakdown(monthContaining: .now,
                                                       displayCurrency: .all, rates: rates)
        let groceries = try XCTUnwrap(breakdown.rows.first(where: { $0.name == "Groceries" }))
        XCTAssertEqual(groceries.spent, 0)
        XCTAssertEqual(groceries.budget, 20_000)
        XCTAssertEqual(groceries.level, .ok)
    }

    // MARK: - expenses(inCategoryNamed:monthContaining:)

    func test_expensesInCategory_otherBucketsNilAndOtherNamed_excludesNamedCategory() async throws {
        let s = try store()
        _ = try await s.logManual(amount: 500, currency: .all, merchant: "Kiosk", categoryName: nil)
        _ = try await s.logManual(amount: 300, currency: .all, merchant: "Corner shop", categoryName: "Other")
        _ = try await s.logManual(amount: 200, currency: .all, merchant: "Diner", categoryName: "Food")

        let other = try await s.expenses(inCategoryNamed: "Other", monthContaining: .now)
        XCTAssertEqual(Set(other.map(\.merchantName)), Set(["Kiosk", "Corner shop"]))

        let food = try await s.expenses(inCategoryNamed: "Food", monthContaining: .now)
        XCTAssertEqual(food.map(\.merchantName), ["Diner"])
    }

    func test_expensesInCategory_matchesLegacyCategoryCaseInsensitively() async throws {
        let s = try store()
        _ = try await s.logManual(amount: 1_200, currency: .all, merchant: "Power bill", categoryName: "Bills")

        // Old installs can retain presentation casing that differs from a newly classified row.
        // The detail page must still show the same transaction the breakdown counted.
        let bills = try await s.expenses(inCategoryNamed: "bills", monthContaining: .now)
        XCTAssertEqual(bills.map(\.merchantName), ["Power bill"])
    }

    // MARK: - assignCategory(named:toExpenseWithKey:)

    func test_assignCategory_movesExpenseFromOtherToNamedCategory() async throws {
        let s = try store()
        let key = try await s.logManual(amount: 400, currency: .all, merchant: "Kiosk", categoryName: nil)

        try await s.assignCategory(named: "Cigarettes", toExpenseWithKey: key)

        let cigs = try await s.expenses(inCategoryNamed: "Cigarettes", monthContaining: .now)
        XCTAssertEqual(cigs.map(\.dedupeKey), [key])

        let other = try await s.expenses(inCategoryNamed: "Other", monthContaining: .now)
        XCTAssertTrue(other.isEmpty)
    }
}
