import Foundation
import Observation
import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

@MainActor
@Observable
public final class SourcesModel {
    private let store: IngestionStore
    public var currency: CurrencyCode
    public private(set) var snapshot: ProvenanceSnapshot?
    public private(set) var loadFailed = false
    /// The Count (GOL-95): the wallet card's state; nil before the first-ever count.
    public private(set) var wallet: WalletSnapshot?

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store; self.currency = currency
    }

    public func load() async {
        do { snapshot = try await store.provenanceSnapshot(displayCurrency: currency); loadFailed = false }
        catch { loadFailed = true }
        wallet = try? await store.walletSnapshot()
    }

    /// Save a count; returns the outcome so the sheet can show the drift moment.
    public func countWallet(_ tally: DenominationTally) async -> WalletCountOutcome? {
        let outcome = try? await store.recordWalletCount(tally)
        await load()
        return outcome
    }

    /// Keep negative drift as a visible "street money" entry.
    public func keepDrift(_ amount: Decimal) async {
        try? await store.logDrift(amount: amount)
        await load()
    }

    public func addIncome(amount: Decimal, currency: CurrencyCode, sourceName: String) async {
        let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount > 0, !name.isEmpty else { return }
        try? await store.logIncome(amount: amount, currency: currency, sourceName: name)
        await load()
    }

    /// Fraction remaining (0...1) for the draining bar.
    public func fraction(_ b: SourceBalance) -> Double {
        guard b.totalInflow > 0 else { return 0 }
        let r = (b.remaining as NSDecimalNumber).doubleValue / (b.totalInflow as NSDecimalNumber).doubleValue
        return min(max(r, 0), 1)
    }

    public func remainingText(_ b: SourceBalance) -> String {
        Money(amount: b.remaining, currency: CurrencyCode(b.currencyCode)).formatted()
    }
    public func unaccountedText() -> String? {
        guard let s = snapshot, s.unaccounted > 0 else { return nil }
        return Money(amount: s.unaccounted, currency: CurrencyCode(s.displayCurrencyCode)).formatted()
    }

    /// A stable, distinct color per source (by its colorIndex) — shared with the funded-by chips
    /// via the design-system palette so the same source is the same color everywhere.
    public func color(_ b: SourceBalance) -> Color {
        GoldengoTheme.sourceColor(b.colorIndex)
    }
}
