import Foundation
import GoldengoCore

/// The read surface the Recent screen depends on. Abstracting it (rather than depending on the
/// concrete `IngestionStore`) lets the UI model be tested against a failing reader so the error
/// path is exercised — `IngestionStore` satisfies it directly.
public protocol ExpensePlanningUpdating: Sendable {
    func updateExpensePlanning(dedupeKey: String, contextName: String?, splits: [TransactionSplit]) async throws
    func updateTransactionKind(dedupeKey: String, kind: TransactionKind) async throws
}

public extension ExpensePlanningUpdating {
    /// Backwards-compatible default for lightweight test readers that only exercise classic edits.
    func updateExpensePlanning(dedupeKey: String, contextName: String?, splits: [TransactionSplit]) async throws {}
    func updateTransactionKind(dedupeKey: String, kind: TransactionKind) async throws {}
}

public protocol RecentExpensesReading: Sendable, ExpensePlanningUpdating {
    func recentExpenses(limit: Int) async throws -> [ExpenseSnapshot]
    func todayTotal(in currency: CurrencyCode, rates: RateTable) async throws -> Decimal
    func dashboardSummary(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> DashboardSummary
    func deleteExpense(dedupeKey: String) async throws
    func restoreExpense(dedupeKey: String) async throws
    func updateExpense(dedupeKey: String, amount: Decimal, currency: CurrencyCode?, merchant: String?, note: String?, categoryName: String?, date: Date, fundedBySourceID: String?) async throws
    func rhythmGhosts(now: Date) async throws -> [RhythmGhost]
    func confirmRhythmGhost(_ ghost: RhythmGhost, amount: Decimal) async throws
    func homeData(in currency: CurrencyCode, rates: RateTable, now: Date, topCategoryLimit: Int) async throws -> HomeData
    /// Logs a tapped "Due" ghost (GOL-92) — the `.automatic` path, so later imports merge into it.
    @discardableResult
    func logAutomatic(amount: Decimal, currency: CurrencyCode, merchant: String?,
                      categoryName: String?, date: Date) async throws -> String
    /// Read-only category totals + budget levels for the month containing `date` — backs Home's
    /// compact Spending card (top rows + over-budget dot) and the full breakdown screen.
    func categoryBreakdown(monthContaining date: Date, displayCurrency: CurrencyCode, rates: RateTable) async throws -> CategoryBreakdown
}

extension IngestionStore: RecentExpensesReading {}
