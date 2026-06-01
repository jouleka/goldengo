import Foundation
import GoldengoCore

/// The read surface the Recent screen depends on. Abstracting it (rather than depending on the
/// concrete `IngestionStore`) lets the UI model be tested against a failing reader so the error
/// path is exercised — `IngestionStore` satisfies it directly.
public protocol RecentExpensesReading: Sendable {
    func recentExpenses(limit: Int) async throws -> [ExpenseSnapshot]
    func todayTotal(in currency: CurrencyCode) async throws -> Decimal
    func dashboardSummary(in currency: CurrencyCode, now: Date, topCategoryLimit: Int) async throws -> DashboardSummary
}

extension IngestionStore: RecentExpensesReading {}
