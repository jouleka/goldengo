import XCTest
import GoldengoCore

final class SubscriptionSettlementPlannerTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    func test_singleMissedMonthlyCharge() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 5, 5), cadence: .monthly, now: day(2026, 6, 10), calendar: cal)
        XCTAssertEqual(due, [day(2026, 6, 5)])
    }

    func test_nothingDue_whenNextChargeIsInTheFuture() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 6, 5), cadence: .monthly, now: day(2026, 6, 10), calendar: cal)
        XCTAssertEqual(due, [])
    }

    func test_multipleMissedPeriods() {
        // Last charge Apr 12, now Jun 20 → May 12 and Jun 12 both fell due (horizon start Apr 21).
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 4, 12), cadence: .monthly, now: day(2026, 6, 20), calendar: cal)
        XCTAssertEqual(due, [day(2026, 5, 12), day(2026, 6, 12)])
    }

    func test_horizonCutoff_dropsOldMisses() {
        // Last charge Jan 5, now Jun 10 → Feb–Jun 5 all fell due, but only those within
        // the trailing 60 days (≥ Apr 11) are settled: May 5 and Jun 5.
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 1, 5), cadence: .monthly, now: day(2026, 6, 10), calendar: cal)
        XCTAssertEqual(due, [day(2026, 5, 5), day(2026, 6, 5)])
    }

    func test_weeklyCadence() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 6, 1), cadence: .weekly, now: day(2026, 6, 16), calendar: cal)
        XCTAssertEqual(due, [day(2026, 6, 8), day(2026, 6, 15)])
    }

    func test_backwardsClock_yieldsNothing() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 6, 10), cadence: .monthly, now: day(2026, 6, 5), calendar: cal)
        XCTAssertEqual(due, [])
    }

    func test_dueExactlyAtNow_isIncluded() {
        // The boundary is at-or-before now (`<=`): a charge due today is settled today,
        // not silently deferred to the next foreground.
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 5, 5), cadence: .monthly, now: day(2026, 6, 5), calendar: cal)
        XCTAssertEqual(due, [day(2026, 6, 5)])
    }

    func test_billingEvidence_toleratesPriceChange_rejectsOneOffs() {
        XCTAssertTrue(SubscriptionSettlementPlanner.isBillingEvidence(amount: 1320, subscriptionAmount: 1200),
                      "+10% is a price change inside the detector's tolerance — still billing evidence")
        XCTAssertTrue(SubscriptionSettlementPlanner.isBillingEvidence(amount: 1200, subscriptionAmount: 1200))
        XCTAssertFalse(SubscriptionSettlementPlanner.isBillingEvidence(amount: 5000, subscriptionAmount: 1200),
                       "A same-merchant one-off (gift card) must not count as billing evidence")
        XCTAssertFalse(SubscriptionSettlementPlanner.isBillingEvidence(amount: 100, subscriptionAmount: 1200))
    }

    func test_monthEndAnchoring_doesNotDriftAfterShortMonth() {
        // Anchored advance: Jan 31 → Feb 28 → Mar 31 (a charge-by-charge walk would drift to Mar 28).
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 1, 31), cadence: .monthly, now: day(2026, 4, 10), calendar: cal)
        XCTAssertEqual(due, [day(2026, 2, 28), day(2026, 3, 31)])
    }
}
