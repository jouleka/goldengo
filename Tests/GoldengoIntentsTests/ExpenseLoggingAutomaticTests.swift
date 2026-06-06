import XCTest
import SwiftData
import GoldengoCore
import GoldengoData
@testable import GoldengoIntents

final class ExpenseLoggingAutomaticTests: XCTestCase {
    func test_log_automaticTrue_recordsAutomaticSource() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await ExpenseLogging.log(amount: 1500, currencyCode: "ALL", merchant: "Spar",
                                         categoryName: nil, store: store, automatic: true)
        let recents = try await store.recentExpenses(limit: 5)
        XCTAssertEqual(recents.first?.source, .automatic)
    }

    func test_log_defaultStaysManual() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await ExpenseLogging.log(amount: 1500, currencyCode: "ALL", merchant: "Spar",
                                         categoryName: nil, store: store)
        let recents = try await store.recentExpenses(limit: 5)
        XCTAssertEqual(recents.first?.source, .manual)
    }
}
