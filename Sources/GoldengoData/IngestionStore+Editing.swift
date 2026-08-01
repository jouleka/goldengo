import Foundation
import SwiftData
import GoldengoCore

extension IngestionStore {
    /// Reclassify an imported/manual credit without rewriting its amount. Refund is distinct from
    /// earned income, so it can reduce the original category's spend and cannot influence payday.
    public func updateTransactionKind(dedupeKey: String, kind: TransactionKind) async throws {
        guard let record = try fetchActiveExpense(dedupeKey: dedupeKey), record.kind != kind else { return }
        record.kindRaw = kind.rawValue
        if kind != .expense {
            for split in record.splits ?? [] { modelContext.delete(split) }
            record.splits = []
            record.subscription = nil
        }
        if kind == .refund {
            record.provenanceSource = nil
            try linkRefundForEditing(record)
        } else {
            record.refundedExpenseKey = nil
        }
        record.updatedAt = .now
        try modelContext.save()
        try refreshSharedTodayTotal()
    }

    private func linkRefundForEditing(_ refund: ExpenseRecord) throws {
        let normalized = MerchantNormalizer.normalize(refund.merchantName)
        guard !normalized.isEmpty else { return }
        let expenseRaw = TransactionKind.expense.rawValue
        let currency = refund.currencyCode
        let refundDate = refund.date
        let earliest = Calendar.current.date(byAdding: .month, value: -12, to: refundDate) ?? .distantPast
        var descriptor = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw && $0.currencyCode == currency
                && $0.date <= refundDate && $0.date >= earliest
        }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.relationshipKeyPathsForPrefetching = [\.category]
        let candidates = try modelContext.fetch(descriptor).filter {
            MerchantNormalizer.normalize($0.merchantName) == normalized
        }
        guard let purchase = candidates.first(where: { $0.amount == refund.amount }) ?? candidates.first
        else { return }
        refund.refundedExpenseKey = purchase.dedupeKey
        if refund.category == nil { refund.category = purchase.category }
        if refund.fundedBySourceID == nil {
            refund.fundedBySourceID = purchase.fundedBySourceID
                ?? (purchase.source == .manual ? FundingPin.wallet : nil)
        }
        if refund.contextName == nil { refund.contextName = purchase.contextName }
    }

    /// Soft-delete an expense via the `isArchived` tombstone (CloudKit-friendly: the deletion
    /// propagates across devices). Reads and totals already exclude archived records.
    public func deleteExpense(dedupeKey: String) throws {
        guard let r = try fetchActiveExpense(dedupeKey: dedupeKey) else { return }
        r.isArchived = true
        r.updatedAt = .now
        try modelContext.save()
        try refreshSharedTodayTotal()   // corrections must reach the lock screen too (review)
    }

    /// Undo a soft-delete by clearing the `isArchived` tombstone, bringing the expense back into
    /// reads and totals. Backs the Recent list's "Undo" toast. No-op if no archived row matches.
    /// Targets the archived record for `key`; delete only ever archives a single record, so there's
    /// nothing to disambiguate here.
    public func restoreExpense(dedupeKey key: String) throws {
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key && $0.isArchived == true })
        fd.fetchLimit = 1
        guard let r = try modelContext.fetch(fd).first else { return }
        r.isArchived = false
        r.updatedAt = .now
        try modelContext.save()
        try refreshSharedTodayTotal()
    }

    /// Edit an existing expense's amount, merchant, note, category, date, and funding pin. An
    /// empty/whitespace merchant, note, or category clears that field. `fundedBySourceID` is the
    /// FINAL pin value, always applied (nil = automatic FIFO) — the edit sheet knows the full state,
    /// so callers pass the row's current pin to keep it, or the new selection.
    public func updateExpense(dedupeKey: String, amount: Decimal, currency: CurrencyCode? = nil,
                              merchant: String?, note: String? = nil, categoryName: String?, date: Date,
                              fundedBySourceID: String? = nil) throws {
        guard let r = try fetchActiveExpense(dedupeKey: dedupeKey) else { return }
        r.fundedBySourceID = fundedBySourceID
        r.amount = amount
        // Preserve the reporting invariant even for callers that do not know about splits. The
        // interactive editor prevents this state, but imports/tests/older clients can still change
        // a parent amount directly. An invalid allocation is less truthful than no allocation.
        if let existing = r.splits, !existing.isEmpty,
           existing.reduce(Decimal.zero, { $0 + $1.amount }) != amount {
            for split in existing { modelContext.delete(split) }
            r.splits = []
        }
        if let currency { r.currencyCode = currency.rawValue }   // nil = keep the existing currency
        let trimmedMerchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        r.merchantName = (trimmedMerchant?.isEmpty ?? true) ? nil : trimmedMerchant
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        r.note = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
        r.date = date
        if let categoryName, !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            r.category = try findOrCreateCategory(named: categoryName)
        } else {
            r.category = nil
        }
        r.updatedAt = .now
        try modelContext.save()
        try refreshSharedTodayTotal()
    }

    /// Updates reporting-only metadata without changing the wallet transaction itself.
    public func updateExpensePlanning(dedupeKey: String, contextName: String?,
                                      splits: [TransactionSplit]) async throws {
        guard let record = try fetchActiveExpense(dedupeKey: dedupeKey) else { return }
        if !splits.isEmpty {
            guard splits.allSatisfy({ $0.amount > 0 && !$0.categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  splits.reduce(Decimal.zero, { $0 + $1.amount }) == record.amount else {
                throw PlanningValidationError.invalidSplits
            }
        }

        let cleanContext = contextName?.trimmingCharacters(in: .whitespacesAndNewlines)
        record.contextName = (cleanContext?.isEmpty ?? true) ? nil : cleanContext
        for old in record.splits ?? [] { modelContext.delete(old) }
        record.splits = try splits.map { split in
            _ = try findOrCreateCategory(named: split.categoryName)
            let allocation = ExpenseSplitRecord(id: split.id, amount: split.amount,
                                                categoryName: split.categoryName)
            allocation.expense = record
            modelContext.insert(allocation)
            return allocation
        }
        record.updatedAt = .now
        try modelContext.save()
        try refreshSharedTodayTotal()
    }

    private func fetchActiveExpense(dedupeKey key: String) throws -> ExpenseRecord? {
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key && $0.isArchived == false })
        fd.fetchLimit = 1
        return try modelContext.fetch(fd).first
    }
}
