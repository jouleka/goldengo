import Foundation
import SwiftData
import GoldengoCore

public struct CategoryTotal: Sendable, Equatable, Identifiable {
    public var name: String
    public var total: Decimal
    public var id: String { name }
    public init(name: String, total: Decimal) { self.name = name; self.total = total }
}

/// `Sendable` snapshot backing the Home dashboard. Single-currency by design (like `todayTotal`).
public struct DashboardSummary: Sendable, Equatable {
    public var monthTotal: Decimal
    public var topCategories: [CategoryTotal]
    public var confirmedSubscriptionCount: Int
    public var confirmedSubscriptionsMonthly: Decimal   // monthly-equivalent sum
    public var currencyCode: String
    public init(monthTotal: Decimal, topCategories: [CategoryTotal], confirmedSubscriptionCount: Int,
                confirmedSubscriptionsMonthly: Decimal, currencyCode: String) {
        self.monthTotal = monthTotal; self.topCategories = topCategories
        self.confirmedSubscriptionCount = confirmedSubscriptionCount
        self.confirmedSubscriptionsMonthly = confirmedSubscriptionsMonthly; self.currencyCode = currencyCode
    }
}

extension IngestionStore {
    /// Aggregates the current calendar month's expense spend, top categories, and the
    /// monthly-equivalent of confirmed subscriptions — all in ONE currency.
    public func dashboardSummary(in currency: CurrencyCode = .all, now: Date = .now,
                                 topCategoryLimit: Int = 4) throws -> DashboardSummary {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
        let expenseRaw = TransactionKind.expense.rawValue
        let code = currency.rawValue

        let monthFd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw && $0.date >= monthStart && $0.currencyCode == code
        })
        let monthRecords = try modelContext.fetch(monthFd)
        let monthTotal = monthRecords.reduce(Decimal(0)) { $0 + $1.amount }

        var byCategory: [String: Decimal] = [:]
        for r in monthRecords { byCategory[r.category?.name ?? "Uncategorized", default: 0] += r.amount }
        let topCategories = byCategory
            .map { CategoryTotal(name: $0.key, total: $0.value) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
            .prefix(topCategoryLimit).map { $0 }

        let confirmed = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>(predicate: #Predicate {
            $0.isConfirmed == true && $0.isDismissed == false && $0.isArchived == false && $0.currencyCode == code
        }))
        let subsMonthly = confirmed.reduce(Decimal(0)) { $0 + Self.monthlyEquivalent($1.amount, cadence: $1.cadence) }

        return DashboardSummary(monthTotal: monthTotal, topCategories: topCategories,
                                confirmedSubscriptionCount: confirmed.count,
                                confirmedSubscriptionsMonthly: subsMonthly, currencyCode: code)
    }

    /// Normalize a cadence amount to a per-month figure.
    static func monthlyEquivalent(_ amount: Decimal, cadence: SubscriptionCadence) -> Decimal {
        switch cadence {
        case .weekly:    return amount * Decimal(52) / Decimal(12)
        case .monthly:   return amount
        case .quarterly: return amount / Decimal(3)
        case .yearly:    return amount / Decimal(12)
        }
    }
}
