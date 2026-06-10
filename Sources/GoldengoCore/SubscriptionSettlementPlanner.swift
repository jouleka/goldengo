import Foundation

/// Plans the due-but-unlogged charge dates for a confirmed subscription (GOL-92).
/// Pure: everything derives from the last *observed* charge, so settling is naturally
/// idempotent — each logged charge becomes the new anchor and a re-run yields [].
public enum SubscriptionSettlementPlanner {
    /// Misses older than this are let go: a sub with no observed charge for ~2 monthly
    /// cycles is questionably alive — don't fabricate deep history.
    public static let horizonDays = 60

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
