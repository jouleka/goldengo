import Foundation
import SwiftData
import GoldengoCore

/// Everything the Home dashboard needs, from ONE expense fetch. Sendable value snapshot.
public struct HomeData: Sendable {
    public let rows: [ExpenseSnapshot]      // recent 50 (both kinds), expense rows carry fundedBy
    public let todayTotal: Decimal          // displayCurrency
    public let summary: DashboardSummary
    public let ghosts: [RhythmGhost]
}

extension IngestionStore {
    /// One fetch of all non-archived expense records → derive recent-50 / today total / month summary
    /// / rhythm ghosts in memory (replacing the four separate reader calls + their redundant scans).
    /// Funding labels use the SharedSummary preferred currency (matching `recentExpenses`); the totals
    /// use `displayCurrency`. The FIFO allocation goes through the fingerprint cache.
    public func homeData(in displayCurrency: CurrencyCode = .all, rates: RateTable,
                         now: Date = .now, topCategoryLimit: Int = 4) throws -> HomeData {
        let expenseRaw = TransactionKind.expense.rawValue

        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.relationshipKeyPathsForPrefetching = [\.category, \.subscription, \.provenanceSource]
        let all = try modelContext.fetch(fd)
        let sources = try modelContext.fetch(FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.isArchived == false }))

        // Provenance funding labels — preferred currency, via the cached allocation.
        let (inflows, outflows) = buildAllocatorInputs(from: all)
        let alloc = allocateCached(inflows: inflows, outflows: outflows, rates: rates,
                                   displayCurrency: SharedSummary().readPreferredCurrency())
        let labels = fundingLabelMap(alloc: alloc, sources: sources)

        // Recent 50 (both kinds, already date-desc); attach fundedBy to expense rows.
        let rows: [ExpenseSnapshot] = all.prefix(50).map { r in
            var snap = makeSnapshot(r)
            if r.kindRaw == expenseRaw { snap.fundedBy = labels[r.dedupeKey] }
            return snap
        }

        // Today total (displayCurrency).
        let startOfToday = Calendar.current.startOfDay(for: now)
        let todayMonies = all
            .filter { $0.kindRaw == expenseRaw && $0.date >= startOfToday }
            .map { Money(amount: $0.amount, currency: CurrencyCode($0.currencyCode)) }
        let todayTotal = CurrencyConverter(table: rates).sum(todayMonies, to: displayCurrency)

        // Month summary (displayCurrency) from a month-filtered slice of the same array.
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
        let monthRecords = all.filter { $0.kindRaw == expenseRaw && $0.date >= monthStart }
        let summary = try makeDashboardSummary(monthRecords: monthRecords, in: displayCurrency,
                                               rates: rates, topCategoryLimit: topCategoryLimit)

        // Ghosts — best-effort so a rhythm failure never blanks the dashboard (matches load()'s try?).
        let ghosts = (try? rhythmGhosts(from: all.filter { $0.kindRaw == expenseRaw }, now: now)) ?? []

        return HomeData(rows: rows, todayTotal: todayTotal, summary: summary, ghosts: ghosts)
    }
}
