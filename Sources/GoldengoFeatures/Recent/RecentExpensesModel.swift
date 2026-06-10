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
    public private(set) var ghosts: [RhythmGhost] = []
    /// Due-but-unlogged subscription charges for the one-tap "Due" section (GOL-92).
    public private(set) var pendingCharges: [PendingSubscriptionCharge] = []
    /// Named sources for the edit sheet's "Paid from" chips (GOL-89); rides along in homeData.
    public private(set) var fundingSources: [FundingSourceOption] = []

    public init(store: any RecentExpensesReading, currency: CurrencyCode = .all) {
        self.reader = store; self.currency = currency
    }

    public func load() async {
        do {
            let rates = ExchangeRateCache().load() ?? SeedRates.table
            let data = try await reader.homeData(in: currency, rates: rates, now: .now, topCategoryLimit: 4)
            rows = data.rows
            todayTotalText = Money(amount: data.todayTotal, currency: currency).formatted()
            summary = data.summary
            ghosts = data.ghosts
            pendingCharges = data.pending
            fundingSources = data.sources
            loadFailed = false
        } catch {
            // Keep any previously-loaded rows on screen; surface the failure so the user can retry.
            loadFailed = true
        }
    }

    /// The rate date behind the converted totals, when conversion was involved (for the staleness caption).
    public var ratesAsOf: Date? { summary?.ratesAsOf }

    /// Soft-delete an expense, then reload so the row disappears.
    public func delete(_ snapshot: ExpenseSnapshot) async {
        try? await reader.deleteExpense(dedupeKey: snapshot.dedupeKey)
        await load()
    }

    /// Undo a soft-delete, then reload so the row reappears (backs the "Undo" toast).
    public func restore(_ snapshot: ExpenseSnapshot) async {
        try? await reader.restoreExpense(dedupeKey: snapshot.dedupeKey)
        await load()
    }

    /// Confirm a daily "usual": log it at `amount` (default = its median), then reload so it clears.
    public func confirm(_ ghost: RhythmGhost, amount: Decimal? = nil) async {
        try? await reader.confirmRhythmGhost(ghost, amount: amount ?? ghost.amount)
        await load()
    }

    /// Log a due subscription charge from its "Due" ghost (GOL-92): backdated to the due date,
    /// `.automatic` so a later statement import merges into it. Reload clears the ghost (the new
    /// row now covers its due date).
    public func logPending(_ charge: PendingSubscriptionCharge) async {
        // Drop the ghost SYNCHRONOUSLY, before the first await: every log is a distinct insert
        // (unique key), so a double-tap during the actor round-trip would double-count. The
        // guard makes a re-entrant second tap a no-op; load() recomputes the true list after.
        guard pendingCharges.contains(charge) else { return }
        pendingCharges.removeAll { $0.id == charge.id }
        _ = try? await reader.logAutomatic(amount: charge.amount,
                                           currency: CurrencyCode(charge.currencyCode),
                                           merchant: charge.merchantName,
                                           categoryName: nil, date: charge.dueDate)
        await load()
    }

    /// Apply an edit to an expense, then reload so the change is reflected. `fundedBySourceID` is the
    /// FINAL funding pin (nil = automatic FIFO) — callers pass the sheet's selection, which starts
    /// from the row's current pin, so an untouched picker leaves the pin unchanged.
    public func update(_ snapshot: ExpenseSnapshot, amount: Decimal, currency: CurrencyCode? = nil,
                       merchant: String?, note: String? = nil, categoryName: String?, date: Date,
                       fundedBySourceID: String?) async {
        try? await reader.updateExpense(dedupeKey: snapshot.dedupeKey, amount: amount, currency: currency,
                                        merchant: merchant, note: note, categoryName: categoryName, date: date,
                                        fundedBySourceID: fundedBySourceID)
        await load()
    }

    public func monthTotalText() -> String {
        Money(amount: summary?.monthTotal ?? 0, currency: currency).formatted()
    }
    /// The month total as a number without the currency symbol — the symbol is shown separately as a
    /// tappable currency control, so the big number can scale to fit instead of clipping.
    public func monthAmountText() -> String {
        Money(amount: summary?.monthTotal ?? 0, currency: currency).amountText()
    }
    public func subscriptionsText() -> String? {
        guard let s = summary, s.confirmedSubscriptionCount > 0 else { return nil }
        let monthly = Money(amount: s.confirmedSubscriptionsMonthly, currency: currency).formatted()
        return "\(s.confirmedSubscriptionCount) confirmed · ~\(monthly)/mo"
    }

    /// Formats a category total in the dashboard's currency (for the Top Categories card).
    public func categoryTotalText(_ total: Decimal) -> String {
        Money(amount: total, currency: currency).formatted()
    }

    /// A category's share of the largest category this month, in 0...1, for the proportional bar.
    /// Returns 0 when there's no spend to compare against.
    public func categoryFraction(_ total: Decimal) -> Double {
        guard let top = summary?.topCategories.map(\.total).max(), top > 0 else { return 0 }
        let value = (total as NSDecimalNumber).doubleValue / (top as NSDecimalNumber).doubleValue
        return min(max(value, 0), 1)
    }
}
