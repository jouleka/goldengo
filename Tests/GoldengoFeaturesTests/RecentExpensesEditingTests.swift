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
    func test_restore_bringsBackADeletedRow() async throws {
        // The Undo toast calls model.restore(snapshot); the row must reappear unchanged.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        let m = RecentExpensesModel(store: store, currency: .all)
        await m.load()
        let snap = m.rows[0]
        await m.delete(snap)
        XCTAssertTrue(m.rows.isEmpty)

        await m.restore(snap)

        XCTAssertEqual(m.rows.count, 1)
        XCTAssertEqual(m.rows.first?.dedupeKey, snap.dedupeKey)
        XCTAssertEqual(m.rows.first?.amount, 250)
    }

    @MainActor
    func test_restore_afterASecondDelete_restoresOnlyTheChosenRow() async throws {
        // The Undo toast is single-slot in the UI, but the model can restore any specific deletion:
        // deleting two rows then restoring the first brings back only that one.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logManual(amount: 100, currency: .all, merchant: "A", categoryName: "Food")
        _ = try await store.logManual(amount: 200, currency: .all, merchant: "B", categoryName: "Food")
        let m = RecentExpensesModel(store: store, currency: .all)
        await m.load()
        let a = try XCTUnwrap(m.rows.first { $0.merchantName == "A" })
        let b = try XCTUnwrap(m.rows.first { $0.merchantName == "B" })
        await m.delete(a)
        await m.delete(b)
        XCTAssertTrue(m.rows.isEmpty)

        await m.restore(a)

        XCTAssertEqual(m.rows.count, 1)
        XCTAssertEqual(m.rows.first?.merchantName, "A")
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
