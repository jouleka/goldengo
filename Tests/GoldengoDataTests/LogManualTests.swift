import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class LogManualTests: XCTestCase {
    func test_logManual_insertsDistinctExpenses_evenWhenIdentical() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2) // two identical coffees are two expenses, not one
    }

    func test_logManual_attachesNamedCategory_findOrCreate() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let key = try await store.logManual(amount: 900, currency: .all, merchant: "Spar", categoryName: "Groceries")
        let snap = try await store.snapshot(dedupeKey: key)
        XCTAssertEqual(snap?.categoryName, "Groceries")
    }
}
