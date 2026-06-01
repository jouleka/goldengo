import XCTest
import GoldengoCore
@testable import GoldengoData

final class ExpenseEditingTests: XCTestCase {
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    func test_deleteExpense_removesFromRecentAndCount() async throws {
        let store = try makeStore()
        let key = try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        let before = try await store.expenseCount()
        XCTAssertEqual(before, 1)

        try await store.deleteExpense(dedupeKey: key)

        let after = try await store.expenseCount()
        XCTAssertEqual(after, 0)
        let recent = try await store.recentExpenses()
        XCTAssertTrue(recent.isEmpty)
        let snap = try await store.snapshot(dedupeKey: key)
        XCTAssertNil(snap)   // archived rows aren't returned
    }

    func test_updateExpense_changesAllFields() async throws {
        let store = try makeStore()
        let key = try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        let newDate = cal.date(from: DateComponents(year: 2026, month: 1, day: 5))!

        try await store.updateExpense(dedupeKey: key, amount: 300, merchant: "Cafe Mocha",
                                      categoryName: "Food", date: newDate)

        let snap = try await store.snapshot(dedupeKey: key)
        XCTAssertEqual(snap?.amount, 300)
        XCTAssertEqual(snap?.merchantName, "Cafe Mocha")
        XCTAssertEqual(snap?.categoryName, "Food")
        XCTAssertEqual(snap?.date, newDate)
    }

    func test_updateExpense_emptyMerchantAndCategory_clears() async throws {
        let store = try makeStore()
        let key = try await store.logManual(amount: 100, currency: .all, merchant: "Shop", categoryName: "Shopping")
        try await store.updateExpense(dedupeKey: key, amount: 100, merchant: "  ", categoryName: "", date: .now)
        let snap = try await store.snapshot(dedupeKey: key)
        XCTAssertNil(snap?.merchantName)
        XCTAssertNil(snap?.categoryName)
    }
}
