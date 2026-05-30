import Foundation
import SwiftData
import GoldengoCore

public enum IngestOutcome: String, Sendable, Equatable { case inserted, merged }

public struct ExpenseSnapshot: Sendable, Equatable {
    public var dedupeKey: String
    public var amount: Decimal
    public var currencyCode: String
    public var source: ExpenseSource
    public var categoryName: String?
}

@ModelActor
public actor IngestionStore {
    /// Insert a transaction, or merge it into the existing non-archived record with the
    /// same dedupeKey. Note: with composite keys (no external id) two genuinely distinct
    /// expenses sharing day+amount+merchant+account will merge — an accepted trade-off
    /// (spec §6) in exchange for collapsing manual+import duplicates.
    public func ingest(_ tx: NormalizedTransaction, source: ExpenseSource = .imported) throws -> IngestOutcome {
        let key = tx.dedupeKey
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key && $0.isArchived == false })
        fd.fetchLimit = 1
        if let existing = try modelContext.fetch(fd).first {
            // Merge: refresh provenance/merchant but keep the first-seen amount/date/currency
            // — an import confirming a manual entry must not silently rewrite what the user typed.
            existing.sourceRaw = source.rawValue
            existing.merchantName = tx.rawMerchant ?? existing.merchantName
            existing.updatedAt = .now
            // Back-fill the merchant default category if the record still has none
            // (e.g. a manual entry made before the merchant->category mapping was learned).
            if existing.category == nil {
                existing.category = try defaultCategory(forMerchant: tx.rawMerchant)
            }
            try modelContext.save()
            return .merged
        }
        let rec = ExpenseRecord(amount: tx.amount, currencyCode: tx.currency.rawValue,
                                date: tx.date, merchantName: tx.rawMerchant,
                                kind: tx.kind, source: source, dedupeKey: key)
        rec.category = try defaultCategory(forMerchant: tx.rawMerchant)
        modelContext.insert(rec)
        try modelContext.save()
        return .inserted
    }

    public func expenseCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.isArchived == false }))
    }

    public func snapshot(dedupeKey key: String) throws -> ExpenseSnapshot? {
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key && $0.isArchived == false })
        fd.fetchLimit = 1
        guard let r = try modelContext.fetch(fd).first else { return nil }
        return ExpenseSnapshot(dedupeKey: r.dedupeKey, amount: r.amount,
                               currencyCode: r.currencyCode, source: r.source,
                               categoryName: r.category?.name)
    }

    /// Remembered default category for a merchant (matched by normalized name), bumping
    /// its usage stats. Returns nil for empty/unknown merchants — the empty guard avoids
    /// matching a merchant row that happens to have an empty normalized name.
    private func defaultCategory(forMerchant rawMerchant: String?) throws -> CategoryRecord? {
        let norm = MerchantNormalizer.normalize(rawMerchant)
        guard !norm.isEmpty else { return nil }
        var mf = FetchDescriptor<MerchantRecord>(predicate: #Predicate { $0.normalizedName == norm })
        mf.fetchLimit = 1
        guard let merchant = try modelContext.fetch(mf).first else { return nil }
        merchant.useCount += 1
        merchant.lastUsed = .now
        return merchant.defaultCategory
    }
}
