import Foundation
import SwiftData
import GoldengoCore

extension IngestionStore {
    /// Soft-delete an expense via the `isArchived` tombstone (CloudKit-friendly: the deletion
    /// propagates across devices). Reads and totals already exclude archived records.
    public func deleteExpense(dedupeKey: String) throws {
        guard let r = try fetchActiveExpense(dedupeKey: dedupeKey) else { return }
        r.isArchived = true
        r.updatedAt = .now
        try modelContext.save()
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
    }

    /// Edit an existing expense's amount, merchant, category, and date. An empty/whitespace
    /// merchant or category clears that field.
    public func updateExpense(dedupeKey: String, amount: Decimal, merchant: String?,
                              categoryName: String?, date: Date) throws {
        guard let r = try fetchActiveExpense(dedupeKey: dedupeKey) else { return }
        r.amount = amount
        let trimmedMerchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        r.merchantName = (trimmedMerchant?.isEmpty ?? true) ? nil : trimmedMerchant
        r.date = date
        if let categoryName, !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            r.category = try findOrCreateCategory(named: categoryName)
        } else {
            r.category = nil
        }
        r.updatedAt = .now
        try modelContext.save()
    }

    private func fetchActiveExpense(dedupeKey key: String) throws -> ExpenseRecord? {
        var fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.dedupeKey == key && $0.isArchived == false })
        fd.fetchLimit = 1
        return try modelContext.fetch(fd).first
    }
}
