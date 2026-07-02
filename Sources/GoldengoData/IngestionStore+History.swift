import Foundation
import SwiftData
import GoldengoCore

/// One period's worth of history for the browser. `Sendable` value snapshot, like `HomeData`.
public struct HistorySnapshot: Sendable, Equatable {
    public let scale: PeriodScale
    public let range: PeriodRange
    public let totalSpent: Decimal       // expense-kind only, converted to the display currency
    public let expenseCount: Int         // expense-kind rows in range
    public let rows: [ExpenseSnapshot]   // ALL kinds in range, date-desc
    public let ratesAsOf: Date?          // set when any conversion happened (drives the staleness caption)

    public init(scale: PeriodScale, range: PeriodRange, totalSpent: Decimal, expenseCount: Int,
                rows: [ExpenseSnapshot], ratesAsOf: Date?) {
        self.scale = scale; self.range = range; self.totalSpent = totalSpent
        self.expenseCount = expenseCount; self.rows = rows; self.ratesAsOf = ratesAsOf
    }
}

/// The read+edit surface the History screen depends on. A focused protocol (not the broad
/// `RecentExpensesReading`) so its view model can be tested against a fake, and so History isn't
/// coupled to Home's dashboard methods. `IngestionStore` satisfies it directly — it already has the
/// edit methods.
public protocol HistoryReading: Sendable {
    func historyData(scale: PeriodScale, anchor: Date, displayCurrency: CurrencyCode,
                     rates: RateTable, now: Date, calendar: Calendar) async throws -> HistorySnapshot
    func deleteExpense(dedupeKey: String) async throws
    func restoreExpense(dedupeKey: String) async throws
    func updateExpense(dedupeKey: String, amount: Decimal, currency: CurrencyCode?, merchant: String?,
                       note: String?, categoryName: String?, date: Date, fundedBySourceID: String?) async throws
}

extension IngestionStore: HistoryReading {}

extension IngestionStore {
    /// Fetch a single period's expenses for the History browser. The fetch is scoped to the period's
    /// half-open date range, so it stays cheap — Day/Week/Month touch a handful of rows, Year one
    /// bounded year. The predicate filters by DATE only (never Decimal — the `#Predicate` Decimal
    /// segfault doesn't apply); the spend total is summed in memory afterwards.
    public func historyData(scale: PeriodScale, anchor: Date, displayCurrency: CurrencyCode,
                            rates: RateTable, now: Date = .now,
                            calendar: Calendar = .current) throws -> HistorySnapshot {
        let range = scale.range(containing: anchor, calendar: calendar)
        let start = range.start, end = range.end
        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.relationshipKeyPathsForPrefetching = [\.category, \.subscription, \.provenanceSource]
        let records = try modelContext.fetch(fd)

        let converter = CurrencyConverter(table: rates)
        let display = displayCurrency.rawValue
        let expenseRaw = TransactionKind.expense.rawValue
        var total = Decimal(0)
        var count = 0
        var usedConversion = false
        for r in records where r.kindRaw == expenseRaw {
            if r.currencyCode != display { usedConversion = true }
            total += (try? converter.convert(r.amount, from: CurrencyCode(r.currencyCode), to: displayCurrency)) ?? 0
            count += 1
        }

        return HistorySnapshot(scale: scale, range: range, totalSpent: total, expenseCount: count,
                               rows: records.map { makeSnapshot($0) },
                               ratesAsOf: usedConversion ? rates.asOf : nil)
    }
}
