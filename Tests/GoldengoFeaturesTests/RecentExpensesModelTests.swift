import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class RecentExpensesModelTests: XCTestCase {
    func test_load_populatesRowsAndTodayTotal() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        let m = RecentExpensesModel(store: store, currency: .all)
        await m.load()
        XCTAssertEqual(m.rows.count, 1)
        XCTAssertEqual(m.todayTotalText, "ALL 250")
        XCTAssertNotNil(m.summary)
        XCTAssertFalse(m.loadFailed)
    }

    func test_load_failure_setsLoadFailed_andDoesNotClobberRows() async throws {
        let m = RecentExpensesModel(store: FailingReader(), currency: .all)
        await m.load()
        XCTAssertTrue(m.loadFailed)
        XCTAssertTrue(m.rows.isEmpty)
        XCTAssertNil(m.summary)
    }
}

/// A reader whose calls always throw — used to exercise the error path that `try?` used to swallow.
private struct FailingReader: RecentExpensesReading {
    struct Boom: Error {}
    func recentExpenses(limit: Int) async throws -> [ExpenseSnapshot] { throw Boom() }
    func todayTotal(in currency: CurrencyCode, rates: RateTable) async throws -> Decimal { throw Boom() }
    func dashboardSummary(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> DashboardSummary { throw Boom() }
    func deleteExpense(dedupeKey: String) async throws { throw Boom() }
    func restoreExpense(dedupeKey: String) async throws { throw Boom() }
    func updateExpense(dedupeKey: String, amount: Decimal, currency: CurrencyCode?, merchant: String?, note: String?, categoryName: String?, date: Date) async throws { throw Boom() }
    func rhythmGhosts(now: Date) async throws -> [RhythmGhost] { throw Boom() }
    func confirmRhythmGhost(_ ghost: RhythmGhost, amount: Decimal) async throws { throw Boom() }
    func homeData(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> HomeData { throw Boom() }
}
