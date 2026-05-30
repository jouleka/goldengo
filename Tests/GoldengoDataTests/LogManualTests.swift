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

    func test_logManual_reusesCategoryCaseInsensitively() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let store = IngestionStore(modelContainer: container)
        try await store.logManual(amount: 100, currency: .all, merchant: nil, categoryName: "Coffee")
        try await store.logManual(amount: 200, currency: .all, merchant: nil, categoryName: "coffee ")
        let ctx = ModelContext(container)
        let cats = try ctx.fetch(FetchDescriptor<CategoryRecord>())
        XCTAssertEqual(cats.count, 1)
    }
}
