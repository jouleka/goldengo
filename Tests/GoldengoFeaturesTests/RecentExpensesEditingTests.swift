import XCTest
import SwiftData
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

final class RecentExpensesEditingTests: XCTestCase {
    @MainActor
    func test_delete_removesRow() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        let m = RecentExpensesModel(store: store, currency: .all)
        await m.load()
        XCTAssertEqual(m.rows.count, 1)
        await m.delete(m.rows[0])
        XCTAssertTrue(m.rows.isEmpty)
    }

    @MainActor
    func test_update_changesRow() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        let m = RecentExpensesModel(store: store, currency: .all)
        await m.load()
        await m.update(m.rows[0], amount: 300, merchant: "Cafe", categoryName: "Food", date: m.rows[0].date)
        XCTAssertEqual(m.rows.first?.amount, 300)
        XCTAssertEqual(m.rows.first?.merchantName, "Cafe")
        XCTAssertEqual(m.rows.first?.categoryName, "Food")
    }
}
