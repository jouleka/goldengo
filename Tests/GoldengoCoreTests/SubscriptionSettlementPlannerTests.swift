import XCTest
import GoldengoCore

final class SubscriptionSettlementPlannerTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    // Forward walk (notBefore == anchor suppresses backfill, matching a sub whose anchor IS
    // its earliest known charge).

    func test_singleMissedMonthlyCharge() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            anchor: day(2026, 5, 5), notBefore: day(2026, 5, 5), cadence: .monthly,
            now: day(2026, 6, 10), calendar: cal)
        XCTAssertEqual(due, [day(2026, 6, 5)])
    }

    func test_nothingDue_whenNextChargeIsInTheFuture() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            anchor: day(2026, 6, 5), notBefore: day(2026, 6, 5), cadence: .monthly,
            now: day(2026, 6, 10), calendar: cal)
        XCTAssertEqual(due, [])
    }

    func test_multipleMissedPeriods() {
        // Last charge Apr 12, now Jun 20 → May 12 and Jun 12 both fell due.
        let due = SubscriptionSettlementPlanner.dueCharges(
            anchor: day(2026, 4, 12), notBefore: day(2026, 4, 12), cadence: .monthly,
            now: day(2026, 6, 20), calendar: cal)
        XCTAssertEqual(due, [day(2026, 5, 12), day(2026, 6, 12)])
    }

    func test_horizonCutoff_dropsOldMisses() {
        // Last charge Jan 5, now Jun 10 → Feb–Jun 5 all fell due, but only those within
        // the trailing 60 days (≥ Apr 11) surface: May 5 and Jun 5.
        let due = SubscriptionSettlementPlanner.dueCharges(
            anchor: day(2026, 1, 5), notBefore: day(2026, 1, 5), cadence: .monthly,
            now: day(2026, 6, 10), calendar: cal)
        XCTAssertEqual(due, [day(2026, 5, 5), day(2026, 6, 5)])
    }

    func test_weeklyCadence() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            anchor: day(2026, 6, 1), notBefore: day(2026, 6, 1), cadence: .weekly,
            now: day(2026, 6, 16), calendar: cal)
        XCTAssertEqual(due, [day(2026, 6, 8), day(2026, 6, 15)])
    }

    func test_backwardsClock_yieldsNothing() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            anchor: day(2026, 6, 10), notBefore: day(2026, 6, 10), cadence: .monthly,
            now: day(2026, 6, 5), calendar: cal)
        XCTAssertEqual(due, [])
    }

    func test_dueExactlyAtNow_isIncluded() {
        // The boundary is at-or-before now (`<=`): a charge due today surfaces today,
        // not silently deferred to the next load.
        let due = SubscriptionSettlementPlanner.dueCharges(
            anchor: day(2026, 5, 5), notBefore: day(2026, 5, 5), cadence: .monthly,
            now: day(2026, 6, 5), calendar: cal)
        XCTAssertEqual(due, [day(2026, 6, 5)])
    }

    func test_monthEndAnchoring_doesNotDriftAfterShortMonth() {
        // Anchored advance: Jan 31 → Feb 28 → Mar 31 (a charge-by-charge walk would drift to Mar 28).
        let due = SubscriptionSettlementPlanner.dueCharges(
            anchor: day(2026, 1, 31), notBefore: day(2026, 1, 31), cadence: .monthly,
            now: day(2026, 4, 10), calendar: cal)
        XCTAssertEqual(due, [day(2026, 2, 28), day(2026, 3, 31)])
    }

    // Backward walk — the anchor may be a freshly-logged LATER due; earlier grid dates
    // inside the horizon must still surface (the round-4 HIGH finding).

    func test_backfill_recoversEarlierGridDates() {
        // The user tapped May 5 first; April's due is still inside the horizon (≥ Mar 13).
        let due = SubscriptionSettlementPlanner.dueCharges(
            anchor: day(2026, 5, 5), notBefore: day(2026, 1, 5), cadence: .monthly,
            now: day(2026, 5, 12), calendar: cal)
        XCTAssertEqual(due, [day(2026, 4, 5)],
                       "Tapping a later ghost must not discard earlier dues")
    }

    func test_backfill_neverInventsPreHistory() {
        // Weekly sub whose first-ever charge is May 4: the backward walk stops at notBefore,
        // never fabricating dues from before the subscription existed.
        let due = SubscriptionSettlementPlanner.dueCharges(
            anchor: day(2026, 6, 1), notBefore: day(2026, 5, 4), cadence: .weekly,
            now: day(2026, 6, 10), calendar: cal)
        XCTAssertEqual(due, [day(2026, 5, 4), day(2026, 5, 11), day(2026, 5, 18), day(2026, 5, 25), day(2026, 6, 8)],
                       "Grid reaches back exactly to the first known charge (those dates are covered upstream) — never Apr 27")
    }

    func test_backfill_monthEndStaysAnchored() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            anchor: day(2026, 3, 31), notBefore: day(2026, 1, 1), cadence: .monthly,
            now: day(2026, 4, 2), calendar: cal)
        XCTAssertEqual(due, [day(2026, 2, 28)],
                       "Backward month-end step is calendar-accurate (Mar 31 → Feb 28; Jan 31 is past the horizon)")
    }

    // Coverage + eligibility helpers (unchanged semantics).

    func test_coverageWindow_staysUnderHalfThePeriod() {
        XCTAssertEqual(SubscriptionSettlementPlanner.coverageWindowDays(for: .weekly), 3)
        XCTAssertEqual(SubscriptionSettlementPlanner.coverageWindowDays(for: .monthly), 15)
        XCTAssertEqual(SubscriptionSettlementPlanner.coverageWindowDays(for: .quarterly), 45)
        XCTAssertEqual(SubscriptionSettlementPlanner.coverageWindowDays(for: .yearly), 182)
        // The invariant that makes coverage safe: adjacent due dates can never cover each other.
        XCTAssertLessThan(SubscriptionSettlementPlanner.coverageWindowDays(for: .weekly) * 2, 7)
        XCTAssertLessThan(SubscriptionSettlementPlanner.coverageWindowDays(for: .monthly) * 2, 31)
    }

    func test_settleableMatchKeys_collapsesCloudKitDuplicates_skipsAmbiguity() {
        typealias C = SubscriptionSettlementPlanner.SettlementCandidate
        // A same-matchKey CloudKit duplicate pair is ONE schedule — it counts (once).
        XCTAssertEqual(SubscriptionSettlementPlanner.settleableMatchKeys(confirmed: [
            C(matchKey: "NETFLIX|monthly|ALL", normalizedMerchant: "NETFLIX", currencyCode: "ALL", isVariableAmount: false),
            C(matchKey: "NETFLIX|monthly|ALL", normalizedMerchant: "NETFLIX", currencyCode: "ALL", isVariableAmount: false),
        ]), ["NETFLIX|monthly|ALL"])
        // Two DISTINCT matchKeys for one merchant+currency = competing schedules — neither.
        XCTAssertEqual(SubscriptionSettlementPlanner.settleableMatchKeys(confirmed: [
            C(matchKey: "NETFLIX|weekly|ALL", normalizedMerchant: "NETFLIX", currencyCode: "ALL", isVariableAmount: false),
            C(matchKey: "NETFLIX|monthly|ALL", normalizedMerchant: "NETFLIX", currencyCode: "ALL", isVariableAmount: false),
        ]), [])
        // The ambiguity poison applies even when one competitor is variable-amount (and thus
        // itself ineligible) — the fixed record's schedule is stale, don't trust it either.
        XCTAssertEqual(SubscriptionSettlementPlanner.settleableMatchKeys(confirmed: [
            C(matchKey: "NETFLIX|monthly|ALL", normalizedMerchant: "NETFLIX", currencyCode: "ALL", isVariableAmount: false),
            C(matchKey: "NETFLIX|weekly|ALL", normalizedMerchant: "NETFLIX", currencyCode: "ALL", isVariableAmount: true),
        ]), [])
        // A variable copy inside a same-matchKey duplicate pair poisons the key (don't guess amounts).
        XCTAssertEqual(SubscriptionSettlementPlanner.settleableMatchKeys(confirmed: [
            C(matchKey: "NETFLIX|monthly|ALL", normalizedMerchant: "NETFLIX", currencyCode: "ALL", isVariableAmount: false),
            C(matchKey: "NETFLIX|monthly|ALL", normalizedMerchant: "NETFLIX", currencyCode: "ALL", isVariableAmount: true),
        ]), [])
        // Different merchants are independent.
        XCTAssertEqual(SubscriptionSettlementPlanner.settleableMatchKeys(confirmed: [
            C(matchKey: "NETFLIX|monthly|ALL", normalizedMerchant: "NETFLIX", currencyCode: "ALL", isVariableAmount: false),
            C(matchKey: "SPOTIFY|monthly|ALL", normalizedMerchant: "SPOTIFY", currencyCode: "ALL", isVariableAmount: false),
        ]), ["NETFLIX|monthly|ALL", "SPOTIFY|monthly|ALL"])
        // Same merchant, different CURRENCY — separate groups, both count.
        XCTAssertEqual(SubscriptionSettlementPlanner.settleableMatchKeys(confirmed: [
            C(matchKey: "NETFLIX|monthly|ALL", normalizedMerchant: "NETFLIX", currencyCode: "ALL", isVariableAmount: false),
            C(matchKey: "NETFLIX|monthly|EUR", normalizedMerchant: "NETFLIX", currencyCode: "EUR", isVariableAmount: false),
        ]), ["NETFLIX|monthly|ALL", "NETFLIX|monthly|EUR"])
    }

    func test_billingEvidence_toleratesPriceChange_rejectsOneOffs() {
        XCTAssertTrue(SubscriptionSettlementPlanner.isBillingEvidence(amount: 1320, subscriptionAmount: 1200),
                      "+10% is a price change inside the detector's tolerance — still billing evidence")
        XCTAssertTrue(SubscriptionSettlementPlanner.isBillingEvidence(amount: 1200, subscriptionAmount: 1200))
        XCTAssertFalse(SubscriptionSettlementPlanner.isBillingEvidence(amount: 5000, subscriptionAmount: 1200),
                       "A same-merchant one-off (gift card) must not count as billing evidence")
        XCTAssertFalse(SubscriptionSettlementPlanner.isBillingEvidence(amount: 100, subscriptionAmount: 1200))
    }
}
