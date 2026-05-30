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
    /// Insert a transaction, or merge into an existing record with the same dedupeKey.
    public func ingest(_ tx: NormalizedTransaction, source: ExpenseSource = .imported) throws -> IngestOutcome {
        let key = tx.dedupeKey
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key && $0.isArchived == false })
        fd.fetchLimit = 1
        if let existing = try modelContext.fetch(fd).first {
            // Merge: prefer the richer provenance and refresh mutable fields.
            existing.sourceRaw = source.rawValue
            existing.merchantName = tx.rawMerchant ?? existing.merchantName
            existing.updatedAt = .now
            try modelContext.save()
            return .merged
        }
        let rec = ExpenseRecord(amount: tx.amount, currencyCode: tx.currency.rawValue,
                                date: tx.date, merchantName: tx.rawMerchant,
                                kind: tx.kind, source: source, dedupeKey: key)
        modelContext.insert(rec)
        try modelContext.save()
        return .inserted
    }

    public func expenseCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.isArchived == false }))
    }

    public func snapshot(dedupeKey key: String) throws -> ExpenseSnapshot? {
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key })
        fd.fetchLimit = 1
        guard let r = try modelContext.fetch(fd).first else { return nil }
        return ExpenseSnapshot(dedupeKey: r.dedupeKey, amount: r.amount,
                               currencyCode: r.currencyCode, source: r.source,
                               categoryName: r.category?.name)
    }
}
