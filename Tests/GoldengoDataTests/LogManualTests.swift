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

    func test_logManual_noCategory_defaultsToOther() async throws {
        // A quick-add with no category and an unknown merchant lands in a real "Other" category
        // (counted + re-assignable), not nil.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let key = try await store.logManual(amount: 100, currency: .all, merchant: nil, categoryName: nil)
        let snap = try await store.snapshot(dedupeKey: key)
        XCTAssertEqual(snap?.categoryName, "Other")
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

    func test_logManual_persistsNote_roundTripsToSnapshot() async throws {
        // The note typed at add time must survive to the snapshot, or the Recent row and Edit view
        // have nothing to show — this is the whole point of the feature.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let key = try await store.logManual(amount: 250, currency: .all, merchant: nil,
                                            note: "lunch with Ana", categoryName: nil)
        let snap = try await store.snapshot(dedupeKey: key)
        XCTAssertEqual(snap?.note, "lunch with Ana")
    }

    func test_logManual_blankNote_storesNil() async throws {
        // A whitespace-only note normalizes to nil so the Recent row falls back to merchant/category
        // instead of rendering a blank primary line.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let key = try await store.logManual(amount: 100, currency: .all, merchant: nil,
                                            note: "   ", categoryName: nil)
        let snap = try await store.snapshot(dedupeKey: key)
        XCTAssertNil(snap?.note)
    }

    func test_logManual_persistsExplicitDate() async throws {
        // A scanned/back-dated receipt must keep the receipt's date, not "now".
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let past = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14
        _ = try await store.logManual(amount: 500, currency: .all, merchant: "Spar",
                                      categoryName: nil, date: past)
        let recents = try await store.recentExpenses(limit: 1)
        XCTAssertEqual(recents.first?.date, past)
    }
}
