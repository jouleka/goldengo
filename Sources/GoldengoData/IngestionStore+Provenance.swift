import Foundation
import SwiftData
import GoldengoCore
#if canImport(WidgetKit)
import WidgetKit
#endif

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

/// A row's funded-by chip content: the joined source names + the first source's palette slot
/// (so the chip's dot matches the Sources tab's color for that source).
public struct FundingTag: Sendable, Equatable {
    public let label: String
    public let colorIndex: Int?
}

/// A pickable funding source for the edit sheet's "Paid from" chips (GOL-89).
public struct FundingSourceOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let colorIndex: Int
    public init(id: String, name: String, colorIndex: Int) {
        self.id = id; self.name = name; self.colorIndex = colorIndex
    }
}

extension IngestionStore {
    /// Find-or-create a source by case-insensitive name (mirrors findOrCreateCategory), then insert a
    /// linked `.income` record. A remittance / pay is just a named inflow to its bank-side pool.
    /// `intoWallet` (GOL-95 v2, "cash in hand"): the money physically entered the WALLET — it is
    /// pinned to the wallet, credits the wallet ledger, and never forms a bank-side pool (the name
    /// is kept on the record as origin memory only; no SourceRecord is created or linked).
    public func logIncome(amount: Decimal, currency: CurrencyCode,
                          sourceName: String, date: Date = .now, intoWallet: Bool = false) throws {
        let rec = ExpenseRecord(amount: amount, currencyCode: currency.rawValue, date: date,
                                merchantName: sourceName.trimmingCharacters(in: .whitespacesAndNewlines),
                                kind: .income, source: .manual,
                                dedupeKey: "income:\(UUID().uuidString)")
        if intoWallet {
            rec.fundedBySourceID = FundingPin.wallet
            // Cash must be VISIBLE in the wallet immediately: a currency with no baseline yet
            // would swallow the inflow invisibly (review finding) — seed a zero baseline just
            // before the income so the line appears showing exactly this money.
            try seedWalletBaselineIfMissing(currency: currency, before: date)
        } else {
            rec.provenanceSource = try findOrCreateSource(named: sourceName, currency: currency)
        }
        modelContext.insert(rec)
        try modelContext.save()
        // Income doesn't change today's EXPENSE total — but "cash in hand" raises the WALLET balance,
        // which the pocket claim is computed from, so that path must republish the claim and refresh
        // the widget (mirroring setWalletBalance). Into-a-source income touches neither the wallet nor
        // the today-total, so it needs no shared-summary refresh.
        if intoWallet {
            try? refreshSharedPocket()
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    // Internal/intra-actor only — returns a non-Sendable @Model, so never expose it across the actor boundary.
    private func findOrCreateSource(named rawName: String, currency: CurrencyCode) throws -> SourceRecord {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = try modelContext.fetch(FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        // Lowest unused palette slot among live sources → distinct colors until all 8 are taken.
        let used = Set(all.map(\.colorIndex))
        let colorIndex = (0..<8).first { !used.contains($0) } ?? (all.count % 8)
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

    /// dedupeKey -> funding tag ("Sister" / "Sister, Cash" + chip color), for expense rows.
    func fundingLabels(displayCurrency: CurrencyCode) throws -> [String: FundingTag] {
        let table = ExchangeRateCache().load() ?? SeedRates.table
        let (alloc, sources) = try compute(rates: table, displayCurrency: displayCurrency)
        return fundingLabelMap(alloc: alloc, sources: sources)
    }

    /// Map a finished allocation + its sources into per-outflow funding tags (label + chip color —
    /// the FIRST funding segment's source sets the dot). Internal so `homeData` can reuse it from
    /// its single shared fetch.
    func fundingLabelMap(alloc: ProvenanceAllocator.Allocation, sources: [SourceRecord]) -> [String: FundingTag] {
        let nameByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.name) })
        let colorByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.colorIndex) })
        var tags: [String: FundingTag] = [:]
        for (outflowID, segs) in alloc.fundingByOutflow {
            let names = segs.compactMap { nameByID[$0.sourceID] }
            guard !names.isEmpty else { continue }
            tags[outflowID] = FundingTag(label: names.joined(separator: ", "),
                                         colorIndex: segs.first.flatMap { colorByID[$0.sourceID] })
        }
        return tags
    }

    /// Build allocator inputs (income → inflows, expense → outflows) from non-archived records.
    /// Internal so `homeData` can reuse a single shared fetch instead of re-fetching.
    func buildAllocatorInputs(from records: [ExpenseRecord])
        -> (inflows: [ProvenanceAllocator.Inflow], outflows: [ProvenanceAllocator.Outflow]) {
        let incomeRaw = TransactionKind.income.rawValue
        let expenseRaw = TransactionKind.expense.rawValue
        let transferRaw = TransactionKind.transfer.rawValue
        let manualRaw = ExpenseSource.manual.rawValue
        var inflows: [ProvenanceAllocator.Inflow] = []
        var outflows: [ProvenanceAllocator.Outflow] = []
        for r in records {
            if r.kindRaw == incomeRaw, r.fundedBySourceID != FundingPin.wallet,
               let sid = r.provenanceSource?.id {
                inflows.append(.init(id: r.dedupeKey, sourceID: sid, amount: r.amount,
                                     currency: CurrencyCode(r.currencyCode), date: r.date))
            } else if r.kindRaw == expenseRaw {
                // GOL-95 v2: cash-funded spends drain the WALLET ledger, not the bank-side
                // pools — the money already left those pools at the ATM (no double-drain).
                let cashFunded = r.fundedBySourceID == FundingPin.wallet
                    || (r.fundedBySourceID == nil && r.sourceRaw == manualRaw)
                if cashFunded { continue }
                outflows.append(.init(id: r.dedupeKey, amount: r.amount,
                                      currency: CurrencyCode(r.currencyCode), date: r.date,
                                      pinnedSourceID: r.fundedBySourceID))
            } else if r.kindRaw == transferRaw {
                // The withdrawal is the moment the bank-side sources drain (unpinned FIFO).
                outflows.append(.init(id: r.dedupeKey, amount: abs(r.amount),
                                      currency: CurrencyCode(r.currencyCode), date: r.date,
                                      pinnedSourceID: nil))
            }
        }
        return (inflows, outflows)
    }

    /// Build allocator inputs from non-archived records and run it (via the fingerprint cache).
    /// Shared by snapshot + labels.
    private func compute(rates: RateTable, displayCurrency: CurrencyCode)
        throws -> (ProvenanceAllocator.Allocation, [SourceRecord]) {
        let sources = try modelContext.fetch(FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        let records = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false }))
        let (inflows, outflows) = buildAllocatorInputs(from: records)
        let alloc = allocateCached(inflows: inflows, outflows: outflows,
                                   rates: rates, displayCurrency: displayCurrency)
        return (alloc, sources)
    }
}
