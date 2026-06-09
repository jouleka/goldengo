import Foundation
import SwiftData
import GoldengoCore

public struct SourceBalance: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let currencyCode: String
    public let colorIndex: Int
    public let totalInflow: Decimal     // source currency
    public let remaining: Decimal       // source currency, >= 0
}

public struct ProvenanceSnapshot: Sendable, Equatable {
    public let sources: [SourceBalance]
    public let unaccounted: Decimal     // displayCurrency
    public let displayCurrencyCode: String
}

extension IngestionStore {
    /// Find-or-create a source by case-insensitive name (mirrors findOrCreateCategory), then insert a
    /// linked `.income` record. A cash withdrawal / remittance / pay is just a named inflow.
    public func logIncome(amount: Decimal, currency: CurrencyCode,
                          sourceName: String, date: Date = .now) throws {
        let src = try findOrCreateSource(named: sourceName, currency: currency)
        let rec = ExpenseRecord(amount: amount, currencyCode: currency.rawValue, date: date,
                                merchantName: src.name, kind: .income, source: .manual,
                                dedupeKey: "income:\(UUID().uuidString)")
        rec.provenanceSource = src
        modelContext.insert(rec)
        try modelContext.save()
        // Income doesn't change today's EXPENSE total, so no shared-summary/widget refresh needed.
    }

    // Internal/intra-actor only — returns a non-Sendable @Model, so never expose it across the actor boundary.
    private func findOrCreateSource(named rawName: String, currency: CurrencyCode) throws -> SourceRecord {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = try modelContext.fetch(FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let colorIndex = all.count % 8
        let s = SourceRecord(name: name, currencyCode: currency.rawValue, colorIndex: colorIndex)
        modelContext.insert(s)
        return s
    }

    /// Per-source balances + Unaccounted, computed via the pure FIFO allocator.
    public func provenanceSnapshot(displayCurrency: CurrencyCode,
                                   rates: RateTable? = nil) throws -> ProvenanceSnapshot {
        let table = rates ?? (ExchangeRateCache().load() ?? SeedRates.table)
        let (alloc, sources) = try compute(rates: table, displayCurrency: displayCurrency)
        var totals: [String: Decimal] = [:]
        for s in sources {
            totals[s.id] = (s.incomes ?? []).filter { !$0.isArchived }.reduce(Decimal(0)) { $0 + $1.amount }
        }
        let balances = sources.map { s in
            SourceBalance(id: s.id, name: s.name, currencyCode: s.currencyCode, colorIndex: s.colorIndex,
                          totalInflow: totals[s.id] ?? 0,
                          remaining: max(0, alloc.remainingBySource[s.id] ?? 0))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return ProvenanceSnapshot(sources: balances, unaccounted: alloc.totalUnaccounted,
                                  displayCurrencyCode: displayCurrency.rawValue)
    }

    /// dedupeKey -> "funded by" label (e.g. "Sister" or "Sister, Cash"), for expense rows.
    func fundingLabels(displayCurrency: CurrencyCode) throws -> [String: String] {
        let table = ExchangeRateCache().load() ?? SeedRates.table
        let (alloc, sources) = try compute(rates: table, displayCurrency: displayCurrency)
        let nameByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.name) })
        var labels: [String: String] = [:]
        for (outflowID, segs) in alloc.fundingByOutflow {
            let names = segs.compactMap { nameByID[$0.sourceID] }
            if !names.isEmpty { labels[outflowID] = names.joined(separator: ", ") }
        }
        return labels
    }

    /// Build allocator inputs from non-archived records and run it. Shared by snapshot + labels.
    private func compute(rates: RateTable, displayCurrency: CurrencyCode)
        throws -> (ProvenanceAllocator.Allocation, [SourceRecord]) {
        let sources = try modelContext.fetch(FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        let incomeRaw = TransactionKind.income.rawValue
        let expenseRaw = TransactionKind.expense.rawValue
        let records = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        var inflows: [ProvenanceAllocator.Inflow] = []
        var outflows: [ProvenanceAllocator.Outflow] = []
        for r in records {
            if r.kindRaw == incomeRaw, let sid = r.provenanceSource?.id {
                inflows.append(.init(id: r.dedupeKey, sourceID: sid, amount: r.amount,
                                     currency: CurrencyCode(r.currencyCode), date: r.date))
            } else if r.kindRaw == expenseRaw {
                outflows.append(.init(id: r.dedupeKey, amount: r.amount,
                                      currency: CurrencyCode(r.currencyCode), date: r.date))
            }
        }
        let alloc = ProvenanceAllocator.allocate(inflows: inflows, outflows: outflows,
                                                 rates: rates, displayCurrency: displayCurrency)
        return (alloc, sources)
    }
}
