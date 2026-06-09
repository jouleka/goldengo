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
        return try rhythmGhosts(from: expenses, now: now)
    }

    /// Derive ghosts from already-fetched non-archived expense records. Internal so `homeData` can
    /// reuse its single shared fetch. Batches the per-ghost merchant-category lookup into ONE fetch.
    func rhythmGhosts(from expenses: [ExpenseRecord], now: Date) throws -> [RhythmGhost] {
        let occurrences = expenses.map {
            TransactionOccurrence(id: $0.dedupeKey, date: $0.date, amount: abs($0.amount),
                                  currency: CurrencyCode($0.currencyCode), merchant: $0.merchantName)
        }
        let patterns = RhythmDetector.detect(occurrences, options: .init(now: now))

        // Merchants already logged today → suppress (no double-count). Deliberately the LOCAL day
        // (the user's "today"), even though RhythmDetector groups by UTC day — don't "align" them:
        // confirmRhythmGhost writes date:.now, so a just-confirmed ghost is always caught by this
        // local-day filter on the next recompute (the suppression invariant).
        let startOfToday = Calendar.current.startOfDay(for: now)
        let loggedTodayMerchants = Set(expenses
            .filter { $0.date >= startOfToday }
            .map { MerchantNormalizer.normalize($0.merchantName) })
        let surfaced = patterns.filter { !loggedTodayMerchants.contains($0.normalizedMerchant) }

        // One fetch for all surfaced ghosts' learned categories (replaces the per-ghost N+1). The
        // merchant set is matched IN MEMORY — capturing a Swift array and calling `.contains` inside a
        // SwiftData #Predicate crashes at runtime (same SIGSEGV class as Decimal-in-#Predicate), so we
        // fetch the (small) merchant table and filter here. Only runs when a ghost actually surfaced.
        let norms = Set(surfaced.map(\.normalizedMerchant))
        let merchants = norms.isEmpty ? [] : try modelContext.fetch(FetchDescriptor<MerchantRecord>())
            .filter { norms.contains($0.normalizedName) }
        let categoryByNorm = Dictionary(merchants.map { ($0.normalizedName, $0.defaultCategory?.name) },
                                        uniquingKeysWith: { first, _ in first })

        return surfaced.map { p in
            RhythmGhost(id: p.id, displayName: p.displayName, normalizedMerchant: p.normalizedMerchant,
                        amount: p.amount, currencyCode: p.currency.rawValue,
                        categoryName: categoryByNorm[p.normalizedMerchant] ?? nil)
        }
    }

    /// Confirm a ghost: log it as a normal manual expense at `amount`, today. Reuses the full
    /// logManual path (auto-category via categoryName:nil, subscription-link, widget refresh).
    public func confirmRhythmGhost(_ ghost: RhythmGhost, amount: Decimal) throws {
        try logManual(amount: amount, currency: CurrencyCode(ghost.currencyCode),
                      merchant: ghost.displayName, categoryName: nil, date: .now)
    }
}
