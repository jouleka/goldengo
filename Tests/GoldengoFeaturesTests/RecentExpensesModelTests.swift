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

    func test_load_populatesSpendingCard_top3Rows_andOverBudgetDot() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        // Four categories so the card must truncate to 3 — proves the preview is capped, not "all rows".
        try await store.logManual(amount: 500, currency: .all, merchant: nil, categoryName: "Food")
        try await store.logManual(amount: 400, currency: .all, merchant: nil, categoryName: "Coffee")
        try await store.logManual(amount: 300, currency: .all, merchant: nil, categoryName: "Transport")
        try await store.logManual(amount: 200, currency: .all, merchant: nil, categoryName: "Fun")
        try await store.setMonthlyBudget(categoryNamed: "Food", cap: 400, currency: .all)   // 500/400 -> over

        let m = RecentExpensesModel(store: store, currency: .all)
        await m.load()

        XCTAssertEqual(m.spendingCardRows.count, 3, "card previews only the top 3 categories, not the full breakdown")
        XCTAssertEqual(m.spendingCardRows.map(\.name), ["Food", "Coffee", "Transport"], "capped-3 keeps the store's spent-desc order")
        XCTAssertTrue(m.hasOverBudgetCategory, "Food is over its cap this month, so the card's dot must show")
    }

    func test_load_noOverBudgetCategory_dotStaysOff() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 100, currency: .all, merchant: nil, categoryName: "Food")
        try await store.setMonthlyBudget(categoryNamed: "Food", cap: 1000, currency: .all)   // 10% -> ok, nowhere near over

        let m = RecentExpensesModel(store: store, currency: .all)
        await m.load()

        XCTAssertFalse(m.hasOverBudgetCategory, "no category is over its cap, so the dot must not show")
    }

    /// Business-rule regression: the Spending card is READ-ONLY. `evaluateBudgetAlerts` persists a
    /// notify-once token so a real push fires only once per category per escalation; if `load()` ever
    /// called it (instead of `categoryBreakdown`), the card's every render would silently consume that
    /// token and a genuine notification would never fire. Proven here: after the app's real notifier
    /// path fires once for the over-budget escalation, several card loads must NOT change that outcome
    /// — a second real evaluation right after still sees nothing NEW to alert on.
    func test_load_neverConsumesTheNotifyOnceBudgetAlertToken() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 500, currency: .all, merchant: nil, categoryName: "Food")
        try await store.setMonthlyBudget(categoryNamed: "Food", cap: 400, currency: .all)   // over

        let rates = RateTable(base: CurrencyCode("ALL"), rates: ["ALL": 1], asOf: Date(timeIntervalSince1970: 1_780_444_800))
        let firstAlerts = try await store.evaluateBudgetAlerts(displayCurrency: .all, rates: rates)
        XCTAssertEqual(firstAlerts.map(\.level), [.over], "the real notifier fires once for the escalation")

        let m = RecentExpensesModel(store: store, currency: .all)
        await m.load()
        await m.load()
        await m.load()   // several card renders/reloads between the two real notifier evaluations

        let secondAlerts = try await store.evaluateBudgetAlerts(displayCurrency: .all, rates: rates)
        XCTAssertTrue(secondAlerts.isEmpty, "the card's reads must not have re-armed the notify-once token")
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
    func categoryBreakdown(monthContaining date: Date, displayCurrency: CurrencyCode, rates: RateTable) async throws -> CategoryBreakdown {
        CategoryBreakdown(monthStart: date, total: 0, rows: [], currencyCode: displayCurrency.rawValue)
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
    func categoryBreakdown(monthContaining date: Date, displayCurrency: CurrencyCode, rates: RateTable) async throws -> CategoryBreakdown { throw Boom() }
}
