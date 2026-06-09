import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class SourcesModel {
    private let store: IngestionStore
    public var currency: CurrencyCode
    public private(set) var snapshot: ProvenanceSnapshot?
    public private(set) var loadFailed = false

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store; self.currency = currency
    }

    public func load() async {
        do { snapshot = try await store.provenanceSnapshot(displayCurrency: currency); loadFailed = false }
        catch { loadFailed = true }
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
}
