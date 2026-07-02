import Foundation
import Observation
import GoldengoCore
import GoldengoData

/// Drives the History period browser: holds the current scale + anchor, loads the matching period,
/// and exposes navigation. Mutations mirror `RecentExpensesModel` so the shared rows behave the same
/// (tap-to-edit, swipe-to-delete with undo).
@MainActor
@Observable
public final class HistoryModel {
    private let reader: any HistoryReading
    public var currency: CurrencyCode
    public private(set) var scale: PeriodScale = .month
    /// A date inside the period currently shown. Navigation shifts this; `load()` resolves its range.
    public private(set) var anchor: Date
    public private(set) var snapshot: HistorySnapshot?
    /// True when the last load threw — the view surfaces it rather than showing a misleading empty period.
    public private(set) var loadFailed = false

    public init(reader: any HistoryReading, currency: CurrencyCode = .all, now: Date = .now) {
        self.reader = reader; self.currency = currency; self.anchor = now
    }

    public func load() async {
        do {
            let rates = ExchangeRateCache().load() ?? SeedRates.table
            snapshot = try await reader.historyData(scale: scale, anchor: anchor, displayCurrency: currency,
                                                    rates: rates, now: .now, calendar: .current)
            loadFailed = false
        } catch {
            loadFailed = true   // keep the prior period on screen; the view offers a retry
        }
    }

    /// Called when the browser opens. Lands on the current period (so a long-lived process never opens
    /// onto a stale launch-time anchor) while preserving the chosen scale, then loads — which also
    /// picks up any currency change made while History was closed.
    public func appear() async {
        anchor = .now
        await load()
    }

    /// Switch granularity and snap back to the present — changing the lens shouldn't strand you in
    /// some unrelated past period.
    public func setScale(_ newScale: PeriodScale) async {
        scale = newScale
        anchor = .now
        await load()
    }

    public func stepBackward() async {
        anchor = scale.anchor(anchor, steppedBy: -1)
        await load()
    }

    /// Forward is allowed only while the shown period has fully elapsed, so the browser can never
    /// land on a period that's entirely in the future.
    public func stepForward() async {
        guard canStepForward else { return }
        anchor = scale.anchor(anchor, steppedBy: 1)
        await load()
    }

    public var canStepForward: Bool { snapshot?.range.hasFullyElapsed(by: .now) ?? false }
    public var periodLabel: String { snapshot.map { scale.label(for: $0.range, now: .now) } ?? "" }
    public var rows: [ExpenseSnapshot] { snapshot?.rows ?? [] }
    public var totalSpentText: String { Money(amount: snapshot?.totalSpent ?? 0, currency: currency).formatted() }
    public var expenseCount: Int { snapshot?.expenseCount ?? 0 }

    /// Day-bucketed for day/week/month; month-bucketed for year — so a Year scrolls by month, not by
    /// hundreds of days.
    public var groups: [DayGroup] {
        scale == .year ? RecentExpensesModel.monthGroups(from: rows, now: .now)
                       : RecentExpensesModel.dayGroups(from: rows, now: .now)
    }

    // MARK: - Mutations (mirror RecentExpensesModel so shared rows behave identically)

    public func delete(_ snapshot: ExpenseSnapshot) async {
        try? await reader.deleteExpense(dedupeKey: snapshot.dedupeKey)
        await load()
    }
    public func restore(_ snapshot: ExpenseSnapshot) async {
        try? await reader.restoreExpense(dedupeKey: snapshot.dedupeKey)
        await load()
    }
    public func update(_ snapshot: ExpenseSnapshot, amount: Decimal, currency: CurrencyCode? = nil,
                       merchant: String?, note: String? = nil, categoryName: String?, date: Date,
                       fundedBySourceID: String?) async {
        try? await reader.updateExpense(dedupeKey: snapshot.dedupeKey, amount: amount, currency: currency,
                                        merchant: merchant, note: note, categoryName: categoryName, date: date,
                                        fundedBySourceID: fundedBySourceID)
        await load()
    }
}
