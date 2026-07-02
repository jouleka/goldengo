import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class SubscriptionsModel {
    public let store: IngestionStore
    public private(set) var rows: [SubscriptionSnapshot] = []
    /// Subscriptions the user marked "not a subscription", surfaced so the dismissal can be undone.
    public private(set) var dismissedRows: [SubscriptionSnapshot] = []
    public private(set) var isLoading = false

    public init(store: IngestionStore) { self.store = store }

    /// Re-run detection, then load the surfaced candidates, then re-sync any scheduled reminders.
    public func load() async {
        guard !isLoading else { return }   // .onAppear / .refreshable / confirm / dismiss can overlap
        isLoading = true
        defer { isLoading = false }
        _ = try? await store.refreshSubscriptions()
        rows = (try? await store.subscriptionCandidates()) ?? []
        dismissedRows = (try? await store.dismissedSubscriptions()) ?? []
        await syncReminders()
    }

    /// Keep scheduled reminders in sync with the confirmed set. The pure decision lives in
    /// `SubscriptionReminders.plannedRequests` (tested); this only reads settings and calls the
    /// scheduler. When the toggle is off, `plannedRequests` returns [] and `sync([])` clears any
    /// stale reminders (self-healing).
    private func syncReminders() async {
        let defaults = UserDefaults(suiteName: SharedSummary.appGroupID) ?? .standard
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let requests = SubscriptionReminders.plannedRequests(
            enabled: defaults.bool(forKey: SharedSummary.remindBeforeChargesKey),
            leadDays: defaults.integer(forKey: SharedSummary.reminderLeadDaysKey),   // 0 when unset → clamped to 1
            candidates: rows, now: .now, calendar: cal)
        await LocalNotificationScheduler.sync(requests)
    }

    public func confirm(_ s: SubscriptionSnapshot) async {
        try? await store.confirmSubscription(matchKey: s.id)
        await load()
    }

    public func dismiss(_ s: SubscriptionSnapshot) async {
        try? await store.dismissSubscription(matchKey: s.id)
        await load()
    }

    /// Undo a dismissal — the subscription re-surfaces as a candidate.
    public func unDismiss(_ s: SubscriptionSnapshot) async {
        try? await store.unDismissSubscription(matchKey: s.id)
        await load()
    }

    /// Track a subscription the user declares directly (Add subscription sheet).
    public func addManual(name: String, amount: Decimal, currency: CurrencyCode,
                          cadence: SubscriptionCadence, nextChargeDate: Date) async {
        try? await store.addManualSubscription(name: name, amount: amount, currency: currency,
                                               cadence: cadence, nextChargeDate: nextChargeDate)
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

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    public func nextChargeText(_ s: SubscriptionSnapshot) -> String {
        "Next: \(dateFormatter.string(from: s.nextChargeDate))"
    }
}
