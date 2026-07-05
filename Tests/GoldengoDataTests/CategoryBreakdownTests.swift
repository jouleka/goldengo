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

    func test_cap_setWithDifferentCase_landsOnSameCategoryAsSpend() async throws {
        // A cap set as "food" and spend logged as "Food" must resolve to ONE CategoryRecord
        // (via findOrCreateCategory), so the cap can never orphan onto a cased duplicate.
        let s = try store()
        try await s.setMonthlyBudget(categoryNamed: "food", cap: 1000)              // lowercase
        _ = try await s.logManual(amount: 900, currency: .all, merchant: nil, categoryName: "Food")  // capitalized
        let b = try await s.categoryBreakdown(monthContaining: .now, displayCurrency: .all, rates: rates)
        let foodRows = b.rows.filter { $0.name.caseInsensitiveCompare("food") == .orderedSame }
        XCTAssertEqual(foodRows.count, 1, "cap and spend must land on one category, not a cased duplicate")
        XCTAssertEqual(foodRows.first?.budget, 1000, "the cap must attach to the same record the spend grouped under")
        XCTAssertNotEqual(foodRows.first?.level, .noBudget)   // 900/1000 → capped, not uncapped
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
