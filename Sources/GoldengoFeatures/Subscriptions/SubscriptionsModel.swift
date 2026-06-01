import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class SubscriptionsModel {
    public let store: IngestionStore
    public private(set) var rows: [SubscriptionSnapshot] = []
    public private(set) var isLoading = false

    public init(store: IngestionStore) { self.store = store }

    /// Re-run detection, then load the surfaced candidates.
    public func load() async {
        isLoading = true
        _ = try? await store.refreshSubscriptions()
        rows = (try? await store.subscriptionCandidates()) ?? []
        isLoading = false
    }

    public func confirm(_ s: SubscriptionSnapshot) async {
        try? await store.confirmSubscription(matchKey: s.id)
        await load()
    }

    public func dismiss(_ s: SubscriptionSnapshot) async {
        try? await store.dismissSubscription(matchKey: s.id)
        await load()
    }

    /// "L 9.99 / month" style label.
    public func amountCadenceText(_ s: SubscriptionSnapshot) -> String {
        let money = Money(amount: s.amount, currency: CurrencyCode(s.currencyCode)).formatted()
        let per: String
        switch s.cadence {
        case .weekly: per = "week"
        case .monthly: per = "month"
        case .quarterly: per = "quarter"
        case .yearly: per = "year"
        }
        return "\(money) / \(per)"
    }

    public func nextChargeText(_ s: SubscriptionSnapshot) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return "Next: \(f.string(from: s.nextChargeDate))"
    }
}
