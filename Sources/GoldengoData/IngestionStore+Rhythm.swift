import Foundation
import SwiftData
import GoldengoCore

/// A pre-drafted daily "usual" — surfaced on Home for one-tap confirm. Computed, never stored.
public struct RhythmGhost: Sendable, Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let normalizedMerchant: String
    public let amount: Decimal
    public let currencyCode: String
    public let categoryName: String?     // learned default (for the row icon); nil → generic
}

extension IngestionStore {
    /// Today's pre-drafted "usuals": active daily patterns NOT yet logged today. Computed each call.
    public func rhythmGhosts(now: Date = .now) throws -> [RhythmGhost] {
        let expenseRaw = TransactionKind.expense.rawValue
        let expenses = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.kindRaw == expenseRaw }))
        let occurrences = expenses.map {
            TransactionOccurrence(id: $0.dedupeKey, date: $0.date, amount: abs($0.amount),
                                  currency: CurrencyCode($0.currencyCode), merchant: $0.merchantName)
        }
        let patterns = RhythmDetector.detect(occurrences, options: .init(now: now))

        // Merchants already logged today (local day) → suppress (no double-count).
        let startOfToday = Calendar.current.startOfDay(for: now)
        let loggedTodayMerchants = Set(expenses
            .filter { $0.date >= startOfToday }
            .map { MerchantNormalizer.normalize($0.merchantName) })

        return patterns.compactMap { p in
            guard !loggedTodayMerchants.contains(p.normalizedMerchant) else { return nil }
            return RhythmGhost(id: p.id, displayName: p.displayName, normalizedMerchant: p.normalizedMerchant,
                               amount: p.amount, currencyCode: p.currency.rawValue,
                               categoryName: try? learnedCategoryName(forNormalized: p.normalizedMerchant))
        }
    }

    /// Confirm a ghost: log it as a normal manual expense at `amount`, today. Reuses the full
    /// logManual path (auto-category via categoryName:nil, subscription-link, widget refresh).
    public func confirmRhythmGhost(_ ghost: RhythmGhost, amount: Decimal) throws {
        try logManual(amount: amount, currency: CurrencyCode(ghost.currencyCode),
                      merchant: ghost.displayName, categoryName: nil, date: .now)
    }

    /// Read-only learned category for a normalized merchant (does NOT bump merchant stats — unlike
    /// the private `defaultCategory` used at log time).
    private func learnedCategoryName(forNormalized norm: String) throws -> String? {
        guard !norm.isEmpty else { return nil }
        var mf = FetchDescriptor<MerchantRecord>(predicate: #Predicate { $0.normalizedName == norm })
        mf.fetchLimit = 1
        return try modelContext.fetch(mf).first?.defaultCategory?.name
    }
}
