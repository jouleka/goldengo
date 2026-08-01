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
public protocol HistoryReading: Sendable, ExpensePlanningUpdating {
    func historyData(scale: PeriodScale, anchor: Date, displayCurrency: CurrencyCode,
                     rates: RateTable, now: Date, calendar: Calendar) async throws -> HistorySnapshot
    func deleteExpense(dedupeKey: String) async throws
    func restoreExpense(dedupeKey: String) async throws
    func updateExpense(dedupeKey: String, amount: Decimal, currency: CurrencyCode?, merchant: String?,
                       note: String?, categoryName: String?, date: Date, fundedBySourceID: String?) async throws
}

public enum TransactionSearchScope: String, Sendable, CaseIterable, Identifiable {
    case all, spending, income, invested
    public var id: String { rawValue }
    public var title: String {
        switch self { case .all: return "All"; case .spending: return "Spent"; case .income: return "Income"; case .invested: return "Invested" }
    }
}

public struct TransactionSearchCriteria: Sendable, Equatable {
    public var query: String = ""
    public var scope: TransactionSearchScope = .all
    public var categoryName: String?
    public var contextName: String?
    public var fundingName: String?
    public var startDate: Date?
    public var endDate: Date?
    public var minimumAmount: Decimal?
    public var maximumAmount: Decimal?

    public init() {}
    public var hasFilters: Bool {
        scope != .all || categoryName != nil || contextName != nil || fundingName != nil
            || startDate != nil || endDate != nil || minimumAmount != nil || maximumAmount != nil
    }
}

public struct TransactionSearchFacets: Sendable, Equatable {
    public let categories: [String]
    public let contexts: [String]
    public let fundingNames: [String]
    public init(categories: [String], contexts: [String], fundingNames: [String]) {
        self.categories = categories; self.contexts = contexts; self.fundingNames = fundingNames
    }
}

public struct TransactionSearchSnapshot: Sendable, Equatable {
    public let rows: [ExpenseSnapshot]
    public let facets: TransactionSearchFacets
    public init(rows: [ExpenseSnapshot], facets: TransactionSearchFacets) {
        self.rows = rows; self.facets = facets
    }
}

public protocol TransactionSearching: Sendable {
    func searchTransactions(_ criteria: TransactionSearchCriteria) async throws -> TransactionSearchSnapshot
}

extension IngestionStore: HistoryReading {}
extension IngestionStore: TransactionSearching {}

extension IngestionStore {
    public func searchTransactions(_ criteria: TransactionSearchCriteria) throws -> TransactionSearchSnapshot {
        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.relationshipKeyPathsForPrefetching = [\.category, \.subscription, \.provenanceSource, \.account, \.splits]
        let records = try modelContext.fetch(fd)
        let sources = try modelContext.fetch(FetchDescriptor<SourceRecord>(predicate: #Predicate { $0.isArchived == false }))
        let sourceNames = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.name) })
        let normalizedQuery = searchKey(criteria.query)

        func fundingName(_ record: ExpenseRecord) -> String {
            if record.fundedBySourceID == FundingPin.wallet { return "Wallet — cash" }
            if let id = record.fundedBySourceID { return sourceNames[id] ?? id }
            return record.source == .manual ? "Wallet — cash" : "Automatic"
        }
        func isInvested(_ record: ExpenseRecord) -> Bool {
            if record.investmentAccountID != nil { return true }
            if SpendingCategoryCatalog.classify(record.category?.name).purpose == .wealth { return true }
            return (record.splits ?? []).contains { SpendingCategoryCatalog.classify($0.categoryName).purpose == .wealth }
        }
        func matches(_ record: ExpenseRecord) -> Bool {
            switch criteria.scope {
            case .all: break
            case .spending: if !record.countsAsSpending { return false }
            case .income: if record.kind != .income { return false }
            case .invested: if !isInvested(record) { return false }
            }
            if let category = criteria.categoryName {
                let parentMatch = record.category?.name.caseInsensitiveCompare(category) == .orderedSame
                let splitMatch = (record.splits ?? []).contains { $0.categoryName.caseInsensitiveCompare(category) == .orderedSame }
                if !parentMatch && !splitMatch { return false }
            }
            if let context = criteria.contextName,
               record.contextName?.caseInsensitiveCompare(context) != .orderedSame { return false }
            if let funding = criteria.fundingName,
               fundingName(record).caseInsensitiveCompare(funding) != .orderedSame { return false }
            if let start = criteria.startDate, record.date < Calendar.current.startOfDay(for: start) { return false }
            if let end = criteria.endDate,
               record.date >= (Calendar.current.date(byAdding: .day, value: 1,
                                                      to: Calendar.current.startOfDay(for: end)) ?? end) { return false }
            if let minimum = criteria.minimumAmount, record.amount < minimum { return false }
            if let maximum = criteria.maximumAmount, record.amount > maximum { return false }
            if !normalizedQuery.isEmpty {
                let searchable = [record.note, record.merchantName, record.category?.name, record.contextName,
                                  fundingName(record), record.account?.name, record.subscription?.displayName,
                                  record.currencyCode, record.kindRaw, NSDecimalNumber(decimal: record.amount).stringValue]
                    .compactMap { $0 }.joined(separator: " ")
                    + " " + (record.splits ?? []).map(\.categoryName).joined(separator: " ")
                if !searchKey(searchable).contains(normalizedQuery) { return false }
            }
            return true
        }

        let rows = records.filter(matches).map { record -> ExpenseSnapshot in
            var snapshot = makeSnapshot(record)
            snapshot.fundedBy = fundingName(record)
            return snapshot
        }
        let categories = Set(records.compactMap { $0.category?.name } + records.flatMap { ($0.splits ?? []).map(\.categoryName) })
        let contexts = Set(records.compactMap(\.contextName))
        let funding = Set(records.map(fundingName))
        return TransactionSearchSnapshot(rows: rows,
            facets: TransactionSearchFacets(categories: categories.sorted(), contexts: contexts.sorted(),
                                            fundingNames: funding.sorted()))
    }

    private func searchKey(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
        fd.relationshipKeyPathsForPrefetching = [\.category, \.subscription, \.provenanceSource, \.splits]
        let records = try modelContext.fetch(fd)

        let converter = CurrencyConverter(table: rates)
        let display = displayCurrency.rawValue
        var total = Decimal(0)
        var count = 0
        var usedConversion = false
        for r in records where r.affectsSpendingTotals {
            if r.currencyCode != display { usedConversion = true }
            total += (try? converter.convert(r.spendingEffect, from: CurrencyCode(r.currencyCode),
                                             to: displayCurrency)) ?? 0
            if r.kind == .expense { count += 1 }
        }

        return HistorySnapshot(scale: scale, range: range, totalSpent: total, expenseCount: count,
                               rows: records.map { makeSnapshot($0) },
                               ratesAsOf: usedConversion ? rates.asOf : nil)
    }
}
