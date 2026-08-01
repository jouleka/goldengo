import Foundation
import SwiftData
import GoldengoCore

public struct MerchantRuleSnapshot: Sendable, Equatable, Identifiable {
    public let id: String
    public let merchantName: String
    public let categoryName: String
    public let useCount: Int
    public let lastUsed: Date
}

extension IngestionStore {
    /// The user-visible form of the existing merchant memory. Rules are explicit and reversible;
    /// a category correction only becomes a rule when its UI says it will.
    public func merchantRules() throws -> [MerchantRuleSnapshot] {
        try modelContext.fetch(FetchDescriptor<MerchantRecord>(
            sortBy: [SortDescriptor(\.lastUsed, order: .reverse), SortDescriptor(\.displayName)]))
        .compactMap { merchant in
            guard let category = merchant.defaultCategory else { return nil }
            return MerchantRuleSnapshot(id: merchant.normalizedName,
                                        merchantName: merchant.displayName,
                                        categoryName: category.name,
                                        useCount: merchant.useCount,
                                        lastUsed: merchant.lastUsed)
        }
    }

    public func setMerchantRule(merchantName rawMerchant: String, categoryName: String) throws {
        let clean = rawMerchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = MerchantNormalizer.normalize(clean)
        guard !clean.isEmpty, !normalized.isEmpty else { return }
        let category = try findOrCreateCategory(named: categoryName)
        var fd = FetchDescriptor<MerchantRecord>(predicate: #Predicate { $0.normalizedName == normalized })
        fd.fetchLimit = 1
        if let existing = try modelContext.fetch(fd).first {
            existing.displayName = clean
            existing.defaultCategory = category
            existing.lastUsed = .now
        } else {
            modelContext.insert(MerchantRecord(displayName: clean, normalizedName: normalized,
                                               lastUsed: .now, defaultCategory: category))
        }
        try modelContext.save()
    }

    public func deleteMerchantRule(id normalizedName: String) throws {
        var fd = FetchDescriptor<MerchantRecord>(predicate: #Predicate { $0.normalizedName == normalizedName })
        fd.fetchLimit = 1
        guard let merchant = try modelContext.fetch(fd).first else { return }
        // Keep the merchant's harmless usage identity for future statistics, but remove the behavior.
        // This avoids CloudKit hard-delete races and makes the action immediately reversible by
        // creating the rule again.
        merchant.defaultCategory = nil
        try modelContext.save()
    }
}
