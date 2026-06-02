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

    func test_restoreExpense_unarchivesADeletedExpense() async throws {
        // Backs the Undo toast: a swipe-deleted expense must come back exactly as it was.
        let store = try makeStore()
        let key = try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        try await store.deleteExpense(dedupeKey: key)
        let afterDelete = try await store.expenseCount()
        XCTAssertEqual(afterDelete, 0)

        try await store.restoreExpense(dedupeKey: key)

        let afterRestore = try await store.expenseCount()
        XCTAssertEqual(afterRestore, 1)
        let snap = try await store.snapshot(dedupeKey: key)
        XCTAssertEqual(snap?.amount, 250)
        XCTAssertEqual(snap?.merchantName, "Coffee")
        XCTAssertEqual(snap?.categoryName, "Coffee")
    }

    func test_restoreExpense_whenNothingArchived_isNoOp() async throws {
        // Undo of a row that was never deleted (or an unknown key) must not crash or resurrect anything.
        let store = try makeStore()
        let key = try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        try await store.restoreExpense(dedupeKey: key)              // nothing archived for this key
        try await store.restoreExpense(dedupeKey: "does-not-exist") // unknown key
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1)                                    // still exactly the one active row
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
