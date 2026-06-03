import Foundation
import SwiftData
import GoldengoCore

public struct CategoryTotal: Sendable, Equatable, Identifiable {
    public var name: String
    public var total: Decimal
    public var id: String { name }
    public init(name: String, total: Decimal) { self.name = name; self.total = total }
}

/// `Sendable` snapshot backing the Home dashboard. Totals are expressed in `currencyCode`, with
/// every expense converted into it via the supplied rate table.
public struct DashboardSummary: Sendable, Equatable {
    public var monthTotal: Decimal
    public var topCategories: [CategoryTotal]
    public var confirmedSubscriptionCount: Int
    public var confirmedSubscriptionsMonthly: Decimal   // monthly-equivalent sum
    public var currencyCode: String
    public var ratesAsOf: Date?                          // the rate date, when any conversion happened
    public init(monthTotal: Decimal, topCategories: [CategoryTotal], confirmedSubscriptionCount: Int,
                confirmedSubscriptionsMonthly: Decimal, currencyCode: String, ratesAsOf: Date?) {
        self.monthTotal = monthTotal; self.topCategories = topCategories
        self.confirmedSubscriptionCount = confirmedSubscriptionCount
        self.confirmedSubscriptionsMonthly = confirmedSubscriptionsMonthly
        self.currencyCode = currencyCode; self.ratesAsOf = ratesAsOf
    }
}

extension IngestionStore {
    /// Aggregates the current month's spend, top categories, and the confirmed-subscription monthly
    /// equivalent — converting every expense into `displayCurrency` via `rates`.
    public func dashboardSummary(in displayCurrency: CurrencyCode = .all, rates: RateTable,
                                 now: Date = .now, topCategoryLimit: Int = 4) throws -> DashboardSummary {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
        let expenseRaw = TransactionKind.expense.rawValue
        let converter = CurrencyConverter(table: rates)
        let display = displayCurrency.rawValue

        let monthFd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw && $0.date >= monthStart
        })
        let monthRecords = try modelContext.fetch(monthFd)

        var monthTotal = Decimal(0)
        var byCategory: [String: Decimal] = [:]
        var usedConversion = false
        for r in monthRecords {
            if r.currencyCode != display { usedConversion = true }
            let v = (try? converter.convert(r.amount, from: CurrencyCode(r.currencyCode), to: displayCurrency)) ?? 0
            monthTotal += v
            byCategory[r.category?.name ?? "Uncategorized", default: 0] += v
        }
        let topCategories = byCategory
            .map { CategoryTotal(name: $0.key, total: $0.value) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
            .prefix(topCategoryLimit).map { $0 }

        let confirmed = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>(predicate: #Predicate {
            $0.isConfirmed == true && $0.isDismissed == false && $0.isArchived == false
        }))
        let subsMonthly = confirmed.reduce(Decimal(0)) { acc, sub in
            if sub.currencyCode != display { usedConversion = true }
            let monthlyEq = Self.monthlyEquivalent(sub.amount, cadence: sub.cadence)
            let v = (try? converter.convert(monthlyEq, from: CurrencyCode(sub.currencyCode), to: displayCurrency)) ?? 0
            return acc + v
        }

        return DashboardSummary(monthTotal: monthTotal, topCategories: topCategories,
                                confirmedSubscriptionCount: confirmed.count,
                                confirmedSubscriptionsMonthly: subsMonthly,
                                currencyCode: display, ratesAsOf: usedConversion ? rates.asOf : nil)
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
