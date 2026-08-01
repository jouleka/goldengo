import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class ExportTests: XCTestCase {
    func test_exportIncludesPlanningSplitsContextAndEscapesCSV() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let store = IngestionStore(modelContainer: container)
        _ = try await store.logManual(amount: 300, currency: .all, merchant: "Shop, One", note: "mixed \"basket\"",
                                      categoryName: "Other", contextName: "Family",
                                      splits: [TransactionSplit(amount: 100, categoryName: "Groceries"),
                                               TransactionSplit(amount: 200, categoryName: "Household")])
        try await store.addGoal(name: "Emergency", targetAmount: 10_000, savedAmount: 1_000,
                                currency: .all, dueDate: nil)
        let csv = try await store.exportFinancialDataCSV()
        XCTAssertTrue(csv.contains("\"transaction\""))
        XCTAssertTrue(csv.contains("\"goal\""))
        XCTAssertTrue(csv.contains("\"Family\""))
        XCTAssertTrue(csv.contains("Groceries:100 | Household:200"))
        XCTAssertTrue(csv.contains("\"Shop, One\""))
        XCTAssertTrue(csv.contains("mixed \"\"basket\"\""))
    }

    func test_exportRestoreRoundTrip_isAdditiveAndIdempotent() async throws {
        let sourceContainer = try ModelContainer.goldengoInMemory()
        let source = IngestionStore(modelContainer: sourceContainer)
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: .now)
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 9, to: start))

        try await source.logIncome(amount: 2_000, currency: .all, sourceName: "Salary")
        _ = try await source.logManual(amount: 175, currency: .all, merchant: "Market",
                                       note: "weekly shop", categoryName: "Groceries",
                                       contextName: "Home")
        try await source.setMonthlyBudget(categoryNamed: "Groceries", cap: 100, currency: .all)
        try await source.addGoal(name: "Emergency", targetAmount: 10_000, savedAmount: 1_250,
                                 currency: .all, dueDate: nil)
        try await source.setSpendingPeriod(startDate: start, endDate: end,
                                           fundingMode: .fixedAmount, startingAmount: 3_000,
                                           currency: .all, cadence: .once)
        let csv = try await source.exportFinancialDataCSV()

        let destinationContainer = try ModelContainer.goldengoInMemory()
        let destination = IngestionStore(modelContainer: destinationContainer)
        // Restore is a merge: local choices win when a stable category already exists.
        try await destination.setMonthlyBudget(categoryNamed: "Groceries", cap: 500, currency: .all)
        let first = try await destination.restoreFinancialDataCSV(csv)
        XCTAssertGreaterThan(first.restored, 0)
        XCTAssertEqual(first.unsupported, 0)

        let transactions = try await destination.recentExpenses(limit: 20)
        XCTAssertEqual(Set(transactions.compactMap(\.merchantName)), ["Market", "Salary"])
        let market = try XCTUnwrap(transactions.first(where: { $0.merchantName == "Market" }))
        XCTAssertEqual(market.categoryName, "Groceries")
        XCTAssertEqual(market.contextName, "Home")
        let categories = try await destination.categoryBreakdown(monthContaining: start,
                                                                  displayCurrency: .all,
                                                                  rates: SeedRates.table)
        XCTAssertEqual(categories.rows.first(where: { $0.name == "Groceries" })?.budget, 500)
        let goals = try await destination.goalSnapshots()
        XCTAssertEqual(goals.first?.savedAmount, 1_250)

        let plan = try await destination.moneyPlanSnapshot(displayCurrency: .all,
                                                            rates: SeedRates.table, now: start)
        XCTAssertEqual(plan.period?.startDate, start)
        XCTAssertEqual(plan.period?.endDate, end)
        XCTAssertEqual(plan.period?.fundingMode, .fixedAmount)
        XCTAssertEqual(plan.period?.startingAmount, 3_000)

        let second = try await destination.restoreFinancialDataCSV(csv)
        XCTAssertEqual(second.restored, 0)
        XCTAssertGreaterThan(second.skippedExisting, 0)
        let transactionsAfterSecondRestore = try await destination.recentExpenses(limit: 20)
        let goalsAfterSecondRestore = try await destination.goalSnapshots()
        XCTAssertEqual(transactionsAfterSecondRestore.count, 2)
        XCTAssertEqual(goalsAfterSecondRestore.count, 1)
    }
}
