import Foundation

/// Plans the due-but-unlogged charge dates for a confirmed subscription (GOL-92).
/// Pure: everything derives from the last *observed* charge, so settling is naturally
/// idempotent — each logged charge becomes the new anchor and a re-run yields [].
public enum SubscriptionSettlementPlanner {
    /// Misses older than this are let go: a sub with no observed charge for ~2 monthly
    /// cycles is questionably alive — don't fabricate deep history.
    public static let horizonDays = 60

    /// A due date already "covered" by any charge row within this many days (tombstones
    /// included) is never settled — so deleting an entry, settle-made or real, is final,
    /// and editing a settle entry's date within its cadence period can't re-fabricate it.
    /// Just under half a period, so adjacent due dates can never cover each other.
    public static func coverageWindowDays(for cadence: SubscriptionCadence) -> Int {
        switch cadence {
        case .weekly:    return 3
        case .monthly:   return 15
        case .quarterly: return 45
        case .yearly:    return 182
        }
    }

    /// One confirmed subscription record's identity, as the settlement sweep sees it.
    public struct SettlementCandidate: Sendable {
        public var matchKey: String
        public var normalizedMerchant: String
        public var currencyCode: String
        public var isVariableAmount: Bool
        public init(matchKey: String, normalizedMerchant: String, currencyCode: String, isVariableAmount: Bool) {
            self.matchKey = matchKey; self.normalizedMerchant = normalizedMerchant
            self.currencyCode = currencyCode; self.isVariableAmount = isVariableAmount
        }
    }

    /// Which matchKeys may settle, given ALL confirmed records (variable ones included):
    /// - Two DISTINCT matchKeys sharing merchant+currency are competing schedules (a series
    ///   that changed cadence) — settle neither, even if one competitor is itself ineligible.
    /// - Same-matchKey duplicates (CloudKit cross-device confirms before sync) are ONE
    ///   schedule — the key settles once, unless any copy is variable-amount (don't guess).
    public static func settleableMatchKeys(confirmed: [SettlementCandidate]) -> Set<String> {
        let groups = Dictionary(grouping: confirmed) { "\($0.normalizedMerchant)|\($0.currencyCode)" }
        var keys = Set<String>()
        for (_, members) in groups {
            let distinct = Set(members.map(\.matchKey))
            guard distinct.count == 1, let key = distinct.first,
                  !members.contains(where: \.isVariableAmount) else { continue }
            keys.insert(key)
        }
        return keys
    }

    /// Whether an observed charge amount is billing evidence for a subscription priced at
    /// `subscriptionAmount` — within the detector's variable-amount tolerance, so a normal
    /// price change still anchors the schedule but a same-merchant one-off (a gift card,
    /// a device purchase) can't hijack it.
    public static func isBillingEvidence(amount: Decimal, subscriptionAmount: Decimal) -> Bool {
        guard subscriptionAmount > 0 else { return amount == subscriptionAmount }
        let a = abs(NSDecimalNumber(decimal: amount).doubleValue)
        let s = NSDecimalNumber(decimal: subscriptionAmount).doubleValue
        return abs(a - s) / s <= SubscriptionDetector.Options().amountTolerance
    }

    /// Charge dates strictly after `lastCharge`, at-or-before `now`, within the trailing
    /// horizon, oldest first. The anchored multi-period advance (`by: k`) keeps the billing
    /// day-of-month stable across short months (Jan 31 → Feb 28 → Mar 31, not Mar 28).
    public static func dueCharges(lastCharge: Date, cadence: SubscriptionCadence,
                                  now: Date, calendar: Calendar) -> [Date] {
        guard lastCharge < now,
              let horizonStart = calendar.date(byAdding: .day, value: -horizonDays, to: now)
        else { return [] }
        var due: [Date] = []
        var k = 1
        var previous = lastCharge
        var next = cadence.advance(lastCharge, by: k, calendar: calendar)
        while next <= now {
            guard next > previous else { return due }   // advance() fell back to its input — never spin
            if next >= horizonStart { due.append(next) }
            previous = next
            k += 1
            next = cadence.advance(lastCharge, by: k, calendar: calendar)
        }
        return due
    }
}
