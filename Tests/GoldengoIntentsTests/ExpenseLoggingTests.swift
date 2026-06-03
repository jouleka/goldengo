import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoIntents

final class ExpenseLoggingTests: XCTestCase {
    func test_logExpense_persistsThroughStore() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = try await ExpenseLogging.log(amount: 1500, currencyCode: "ALL",
                                                   merchant: nil, categoryName: "Groceries", store: store)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1)
        XCTAssertTrue(summary.contains("1,500"))
    }

    func test_logExpense_persistsNote_andIncludesItInConfirmation() async throws {
        // The note captured at the trigger must reach the saved expense (the whole point of the
        // feature), and the confirmation must echo it so the user knows what was logged without
        // ever opening the app.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = try await ExpenseLogging.log(amount: 500, currencyCode: "ALL",
                                                   merchant: nil, note: "coffee", categoryName: nil, store: store)
        let rows = try await store.recentExpenses()
        XCTAssertEqual(rows.first?.note, "coffee")
        XCTAssertTrue(summary.contains("coffee"))
    }

    func test_logExpense_blankNote_storesNilAndPlainConfirmation() async throws {
        // A blank/whitespace note normalizes to nil (so the Recent row falls back cleanly) and must
        // not leave a dangling "— " in the confirmation.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = try await ExpenseLogging.log(amount: 500, currencyCode: "ALL",
                                                   merchant: nil, note: "   ", categoryName: nil, store: store)
        let rows = try await store.recentExpenses()
        XCTAssertNil(rows.first?.note)
        XCTAssertFalse(summary.contains("—"))
    }
}
