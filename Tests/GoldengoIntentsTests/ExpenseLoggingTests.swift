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
}
