import Foundation
import Observation
import GoldengoCore
import GoldengoData

/// Backs the evening reflection: today's morning intention (if any), today's usuals to confirm,
/// and a calm spend recap. `summary` is injectable so the intention read is testable in isolation.
@MainActor
@Observable
public final class EveningModel {
    private let store: IngestionStore
    private let summary: SharedSummary
    public var currency: CurrencyCode
    public private(set) var intention: String?
    public private(set) var ghosts: [RhythmGhost] = []
    public private(set) var todayTotalText: String = ""

    public init(store: IngestionStore, currency: CurrencyCode = .all, summary: SharedSummary = SharedSummary()) {
        self.store = store; self.currency = currency; self.summary = summary
    }

    public func load() async {
        // Only show the intention if it was set TODAY (a stale prior-day note is not "this morning").
        if let saved = summary.readIntention(), Calendar.current.isDate(saved.date, inSameDayAs: .now) {
            intention = saved.text
        } else {
            intention = nil
        }
        let rates = ExchangeRateCache().load() ?? SeedRates.table
        ghosts = (try? await store.rhythmGhosts(now: .now)) ?? []
        let total = (try? await store.todayTotal(in: currency, rates: rates)) ?? 0
        todayTotalText = Money(amount: total, currency: currency).formatted()
    }

    /// Confirm a usual (logs it at its median), then reload so it clears from the list.
    public func confirm(_ ghost: RhythmGhost) async {
        try? await store.confirmRhythmGhost(ghost, amount: ghost.amount)
        await load()
    }

    /// Record that tonight's reflection is done (drives the once-per-day suppression).
    public func markReflected() { summary.setReflected(on: .now) }
}
