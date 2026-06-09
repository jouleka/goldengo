import Foundation
import GoldengoCore

/// The read surface the Recent screen depends on. Abstracting it (rather than depending on the
/// concrete `IngestionStore`) lets the UI model be tested against a failing reader so the error
/// path is exercised — `IngestionStore` satisfies it directly.
public protocol RecentExpensesReading: Sendable {
    func recentExpenses(limit: Int) async throws -> [ExpenseSnapshot]
    func todayTotal(in currency: CurrencyCode, rates: RateTable) async throws -> Decimal
    func dashboardSummary(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> DashboardSummary
    func deleteExpense(dedupeKey: String) async throws
    func restoreExpense(dedupeKey: String) async throws
    func updateExpense(dedupeKey: String, amount: Decimal, currency: CurrencyCode?, merchant: String?, note: String?, categoryName: String?, date: Date) async throws
    func rhythmGhosts(now: Date) async throws -> [RhythmGhost]
    func confirmRhythmGhost(_ ghost: RhythmGhost, amount: Decimal) async throws
    func homeData(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> HomeData
}

extension IngestionStore: RecentExpensesReading {}
