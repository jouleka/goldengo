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
    public var date: Date
    public var merchantName: String?
    public var kind: TransactionKind
    public var subscriptionName: String?
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
            try linkToConfirmedSubscription(existing)
            try modelContext.save()
            return .merged
        }
        let rec = ExpenseRecord(amount: tx.amount, currencyCode: tx.currency.rawValue,
                                date: tx.date, merchantName: tx.rawMerchant,
                                kind: tx.kind, source: source, dedupeKey: key)
        rec.category = try defaultCategory(forMerchant: tx.rawMerchant)
        modelContext.insert(rec)
        try linkToConfirmedSubscription(rec)
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
        return makeSnapshot(r)
    }

    public func recentExpenses(limit: Int = 20) throws -> [ExpenseSnapshot] {
        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = limit
        return try modelContext.fetch(fd).map(makeSnapshot)
    }

    /// Sum of today's expense-kind amounts in ONE currency. Note: `.all` is the ISO 4217
    /// code for the Albanian lek ("ALL") — the user's primary currency — NOT a wildcard.
    /// This method is single-currency by design; a true cross-currency total would need
    /// FX conversion (spec §6 ExchangeRate) and is out of scope for the MVP.
    public func todayTotal(in currency: CurrencyCode = .all) throws -> Decimal {
        let start = Calendar.current.startOfDay(for: .now)
        let expenseRaw = TransactionKind.expense.rawValue
        let code = currency.rawValue
        let fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw && $0.date >= start && $0.currencyCode == code
        })
        return try modelContext.fetch(fd).reduce(Decimal(0)) { $0 + $1.amount }
    }

    private func makeSnapshot(_ r: ExpenseRecord) -> ExpenseSnapshot {
        ExpenseSnapshot(dedupeKey: r.dedupeKey, amount: r.amount, currencyCode: r.currencyCode,
                        source: r.source, categoryName: r.category?.name,
                        date: r.date, merchantName: r.merchantName, kind: r.kind,
                        subscriptionName: r.subscription?.displayName)
    }

    /// Link an expense-kind record to a CONFIRMED subscription with the same normalized merchant + currency.
    private func linkToConfirmedSubscription(_ rec: ExpenseRecord) throws {
        guard rec.kindRaw == TransactionKind.expense.rawValue else { return }
        let norm = MerchantNormalizer.normalize(rec.merchantName)
        guard !norm.isEmpty else { return }
        let confirmed = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate { $0.isConfirmed == true && $0.isDismissed == false && $0.isArchived == false }))
        if let match = confirmed.first(where: { $0.normalizedMerchant == norm && $0.currencyCode == rec.currencyCode }) {
            rec.subscription = match
        }
    }

    /// Logs a user-entered expense. Always a distinct insert (unique key) so identical
    /// same-day purchases are never collapsed. Returns the new record's dedupeKey.
    @discardableResult
    public func logManual(amount: Decimal, currency: CurrencyCode,
                          merchant: String?, categoryName: String?) throws -> String {
        let key = "manual:\(UUID().uuidString)"
        let rec = ExpenseRecord(amount: amount, currencyCode: currency.rawValue, date: .now,
                                merchantName: merchant, kind: .expense, source: .manual, dedupeKey: key)
        if let categoryName, !categoryName.isEmpty {
            rec.category = try findOrCreateCategory(named: categoryName)
        } else {
            rec.category = try defaultCategory(forMerchant: merchant)
        }
        modelContext.insert(rec)
        try linkToConfirmedSubscription(rec)
        try modelContext.save()
        let total = try todayTotal(in: .all)
        SharedSummary().writeTodayTotal(Money(amount: total, currency: .all).formatted())
        return key
    }

    private func findOrCreateCategory(named rawName: String) throws -> CategoryRecord {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Case-insensitive reuse so free-text from Siri/Shortcuts doesn't spawn "Coffee"/"coffee".
        let all = try modelContext.fetch(FetchDescriptor<CategoryRecord>())
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let c = CategoryRecord(name: name)
        modelContext.insert(c)
        return c
    }

    /// Remembered default category for a merchant (matched by normalized name), bumping
    /// its usage stats. Returns nil for empty/unknown merchants — the empty guard avoids
    /// matching a merchant row that happens to have an empty normalized name.
    public struct ImportSummary: Sendable, Equatable { public var imported: Int; public var deduped: Int }

    public func importStatement(_ transactions: [NormalizedTransaction], fileName: String) throws -> ImportSummary {
        var imported = 0, deduped = 0
        for tx in transactions {
            switch try ingest(tx, source: .imported) {
            case .inserted: imported += 1
            case .merged:   deduped += 1
            }
        }
        modelContext.insert(ImportBatch(fileName: fileName, rowCount: transactions.count,
                                        importedCount: imported, dedupedCount: deduped))
        try modelContext.save()
        let total = try todayTotal(in: .all)
        SharedSummary().writeTodayTotal(Money(amount: total, currency: .all).formatted())
        return ImportSummary(imported: imported, deduped: deduped)
    }

    public func importBatchCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ImportBatch>())
    }

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
