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
    /// The wallet's per-currency lines (GOL-95 v2); empty before the first balance is set.
    public private(set) var wallet: [WalletBalance] = []
    /// One-shot: a pocket-widget tap should land ON the Adjust screen (GOL-98). In-memory on
    /// purpose — a persisted flag outlives a killed launch and replays the navigation days
    /// later as an unprompted sheet (review); losing one tap to a process death is the
    /// acceptable failure, surprise navigation is not.
    public var pendingWalletAdjust = false

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store; self.currency = currency
    }

    public func load() async {
        do { snapshot = try await store.provenanceSnapshot(displayCurrency: currency); loadFailed = false }
        catch { loadFailed = true }
        wallet = (try? await store.walletBalances()) ?? []
    }

    /// Set what's actually in the wallet for one currency (typed, or via the optional tally).
    public func setWalletBalance(_ total: Decimal, currency: CurrencyCode,
                                 tally: DenominationTally?) async -> WalletSetOutcome? {
        let outcome = try? await store.setWalletBalance(total, currency: currency, tally: tally)
        await load()
        return outcome
    }

    /// Stop tracking a currency's wallet line (money records stay; the line just goes).
    public func removeWalletCurrency(_ currency: CurrencyCode) async {
        try? await store.removeWalletCurrency(currency)
        await load()
    }

    /// Set what's actually left in a source (higher → income; lower → visible Unaccounted).
    public func setSourceRemaining(_ amount: Decimal, source: SourceBalance) async {
        try? await store.setSourceRemaining(amount, sourceID: source.id)
        await load()
    }

    /// Rename a source (refused when another live source already uses the name).
    public func renameSource(_ source: SourceBalance, to name: String) async {
        try? await store.renameSource(id: source.id, to: name)
        await load()
    }

    /// Delete a source — its pool and income records archive together.
    public func deleteSource(_ source: SourceBalance) async {
        try? await store.deleteSource(id: source.id)
        await load()
    }

    public func addIncome(amount: Decimal, currency: CurrencyCode, sourceName: String,
                          intoWallet: Bool = false, date: Date = .now) async {
        let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount > 0, !name.isEmpty else { return }
        try? await store.logIncome(amount: amount, currency: currency, sourceName: name,
                                   date: date, intoWallet: intoWallet)
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
