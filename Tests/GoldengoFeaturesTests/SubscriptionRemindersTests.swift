import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

final class SubscriptionRemindersTests: XCTestCase {
    private func snap(_ id: String, _ name: String, confirmed: Bool) -> SubscriptionSnapshot {
        SubscriptionSnapshot(id: id, displayName: name, amount: 1200, currencyCode: "ALL",
                             cadence: .monthly, nextChargeDate: Date(timeIntervalSince1970: 1_800_000_000),
                             occurrenceCount: 3, confidence: 0.8, isVariableAmount: false,
                             hadTrial: false, isConfirmed: confirmed)
    }

    func test_inputs_onlyFromConfirmed() {
        let inputs = SubscriptionReminders.inputs(from: [
            snap("a|monthly|ALL", "Netflix", confirmed: true),
            snap("b|monthly|ALL", "Spotify", confirmed: false),
        ])
        XCTAssertEqual(inputs.map(\.id), ["a|monthly|ALL"])
        XCTAssertTrue(inputs[0].title.contains("Netflix"))
        XCTAssertFalse(inputs[0].body.isEmpty)
        XCTAssertEqual(inputs[0].nextCharge, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func test_inputs_emptyWhenNoneConfirmed() {
        XCTAssertTrue(SubscriptionReminders.inputs(from: [snap("a", "X", confirmed: false)]).isEmpty)
    }

    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private var pastNow: Date { Date(timeIntervalSince1970: 1_700_000_000) }   // ~2023, before snap nextCharge (~2027)

    func test_plannedRequests_disabled_returnsEmpty() {
        let cands = [snap("a", "Netflix", confirmed: true)]
        XCTAssertTrue(SubscriptionReminders.plannedRequests(
            enabled: false, leadDays: 1, candidates: cands, now: pastNow, calendar: utc).isEmpty)
    }

    func test_plannedRequests_clampsUnsetLeadDaysToOne() {
        // UserDefaults.integer returns 0 when the key is unset; plannedRequests must clamp to 1.
        let cands = [snap("a", "Netflix", confirmed: true)]
        let zero = SubscriptionReminders.plannedRequests(enabled: true, leadDays: 0, candidates: cands, now: pastNow, calendar: utc)
        let one = SubscriptionReminders.plannedRequests(enabled: true, leadDays: 1, candidates: cands, now: pastNow, calendar: utc)
        XCTAssertEqual(zero, one)
        XCTAssertEqual(zero.count, 1)
    }

    func test_plannedRequests_onlyConfirmed() {
        let cands = [snap("a", "Netflix", confirmed: true), snap("b", "Spotify", confirmed: false)]
        let reqs = SubscriptionReminders.plannedRequests(enabled: true, leadDays: 1, candidates: cands, now: pastNow, calendar: utc)
        XCTAssertEqual(reqs.map(\.id), ["a"])
    }
}
