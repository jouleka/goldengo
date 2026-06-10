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

    func test_doubleTappingADueGhost_logsExactlyOnce() async throws {
        let ghost = PendingSubscriptionCharge(matchKey: "NETFLIX|monthly|ALL", displayName: "Netflix",
                                              merchantName: "Netflix", amount: 1200, currencyCode: "ALL",
                                              dueDate: Date(timeIntervalSinceReferenceDate: 0))
        let reader = CountingReader(pending: [ghost])
        let m = RecentExpensesModel(store: reader, currency: .all)
        await m.load()
        XCTAssertEqual(m.pendingCharges.count, 1)
        // Two taps land before the first round-trip completes. logPending drops the ghost
        // synchronously before its first await, so the second call must be a no-op — a unique
        // dedupeKey per log means a second insert would silently double-count the charge.
        async let first: Void = m.logPending(ghost)
        async let second: Void = m.logPending(ghost)
        _ = await (first, second)
        let count = await reader.logCount
        XCTAssertEqual(count, 1, "Re-entrant taps on one ghost must collapse to a single log")
    }
}

/// A reader that serves one fixed pending ghost and counts logAutomatic calls.
private actor CountingReader: RecentExpensesReading {
    private let pending: [PendingSubscriptionCharge]
    private(set) var logCount = 0
    init(pending: [PendingSubscriptionCharge]) { self.pending = pending }

    func recentExpenses(limit: Int) async throws -> [ExpenseSnapshot] { [] }
    func todayTotal(in currency: CurrencyCode, rates: RateTable) async throws -> Decimal { 0 }
    func dashboardSummary(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> DashboardSummary {
        DashboardSummary(monthTotal: 0, topCategories: [], confirmedSubscriptionCount: 0,
                         confirmedSubscriptionsMonthly: 0, currencyCode: currency.rawValue, ratesAsOf: nil)
    }
    func deleteExpense(dedupeKey: String) async throws {}
    func restoreExpense(dedupeKey: String) async throws {}
    func updateExpense(dedupeKey: String, amount: Decimal, currency: CurrencyCode?, merchant: String?, note: String?, categoryName: String?, date: Date, fundedBySourceID: String?) async throws {}
    func rhythmGhosts(now: Date) async throws -> [RhythmGhost] { [] }
    func confirmRhythmGhost(_ ghost: RhythmGhost, amount: Decimal) async throws {}
    func homeData(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> HomeData {
        HomeData(rows: [], todayTotal: 0,
                 summary: DashboardSummary(monthTotal: 0, topCategories: [], confirmedSubscriptionCount: 0,
                                           confirmedSubscriptionsMonthly: 0, currencyCode: currency.rawValue,
                                           ratesAsOf: nil),
                 ghosts: [], sources: [], pending: pending)
    }
    @discardableResult
    func logAutomatic(amount: Decimal, currency: CurrencyCode, merchant: String?,
                      categoryName: String?, date: Date) async throws -> String {
        logCount += 1
        return "auto:test-\(logCount)"
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
    func updateExpense(dedupeKey: String, amount: Decimal, currency: CurrencyCode?, merchant: String?, note: String?, categoryName: String?, date: Date, fundedBySourceID: String?) async throws { throw Boom() }
    func rhythmGhosts(now: Date) async throws -> [RhythmGhost] { throw Boom() }
    func confirmRhythmGhost(_ ghost: RhythmGhost, amount: Decimal) async throws { throw Boom() }
    func homeData(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> HomeData { throw Boom() }
    func logAutomatic(amount: Decimal, currency: CurrencyCode, merchant: String?,
                      categoryName: String?, date: Date) async throws -> String { throw Boom() }
}
