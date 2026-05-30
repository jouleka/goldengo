import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class ReadMethodsTests: XCTestCase {
    func test_recentExpenses_returnsAllNonArchived() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 100, currency: .all, merchant: "A", categoryName: nil)
        try await store.logManual(amount: 200, currency: .all, merchant: "B", categoryName: nil)
        let recents = try await store.recentExpenses(limit: 10)
        XCTAssertEqual(recents.count, 2)
        XCTAssertEqual(Set(recents.map(\.amount)), [100, 200])
    }

    func test_todayTotal_sumsTodaysExpenses() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 100, currency: .all, merchant: nil, categoryName: nil)
        try await store.logManual(amount: 250, currency: .all, merchant: nil, categoryName: nil)
        let total = try await store.todayTotal()
        XCTAssertEqual(total, 350)
    }
}
