import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class RecentExpensesModel {
    private let reader: any RecentExpensesReading
    public var currency: CurrencyCode
    public private(set) var rows: [ExpenseSnapshot] = []
    public private(set) var todayTotalText: String = ""
    public private(set) var summary: DashboardSummary?
    /// True when the last load threw. The view surfaces this instead of silently showing an empty
    /// list (errors used to be swallowed with `try?`).
    public private(set) var loadFailed = false

    public init(store: any RecentExpensesReading, currency: CurrencyCode = .all) {
        self.reader = store; self.currency = currency
    }

    public func load() async {
        do {
            let fetched = try await reader.recentExpenses(limit: 50)
            let total = try await reader.todayTotal(in: currency)
            rows = fetched
            todayTotalText = Money(amount: total, currency: currency).formatted()
            summary = try await reader.dashboardSummary(in: currency, now: .now, topCategoryLimit: 4)
            loadFailed = false
        } catch {
            // Keep any previously-loaded rows on screen; surface the failure so the user can retry.
            loadFailed = true
        }
    }

    public func monthTotalText() -> String {
        Money(amount: summary?.monthTotal ?? 0, currency: currency).formatted()
    }
    public func subscriptionsText() -> String? {
        guard let s = summary, s.confirmedSubscriptionCount > 0 else { return nil }
        let monthly = Money(amount: s.confirmedSubscriptionsMonthly, currency: currency).formatted()
        return "\(s.confirmedSubscriptionCount) confirmed · ~\(monthly)/mo"
    }
}
