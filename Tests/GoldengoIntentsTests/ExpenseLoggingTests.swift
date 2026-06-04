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

    func test_log_unknownMerchant_keepsMerchant_andCategorizesOther() async throws {
        // An auto-captured Apple Pay payment passes a merchant and no category. The merchant must be
        // kept (it labels the Recent row and feeds subscription detection) and an unrecognised merchant
        // must land in a real "Other" category — never silently uncategorized.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = try await ExpenseLogging.log(amount: 350, currencyCode: "ALL",
                                                   merchant: "Tiny Cafe", categoryName: nil, store: store)
        let snap = try await store.recentExpenses().first
        XCTAssertEqual(snap?.merchantName, "Tiny Cafe")
        XCTAssertEqual(snap?.categoryName, "Other")
        XCTAssertTrue(summary.contains("350"))
    }
}
