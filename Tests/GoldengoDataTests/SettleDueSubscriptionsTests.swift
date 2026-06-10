import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class SettleDueSubscriptionsTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    /// Three monthly Netflix charges (Jan–Mar 5) — enough for the detector's monthly bar.
    /// Pass distinct amounts to make the detector flag the subscription variable-amount.
    private func seedMonthlyNetflix(_ store: IngestionStore, amounts: [Decimal] = [1200, 1200, 1200]) async throws {
        for (i, m) in [1, 2, 3].enumerated() {
            _ = try await store.ingest(NormalizedTransaction(
                externalID: "nf\(i)", amount: amounts[i], currency: .all, date: day(2026, m, 5),
                rawMerchant: "Netflix", kind: .expense, accountRef: "card"), source: .imported)
        }
    }
    private func subscriptionKey(_ store: IngestionStore, named name: String) async throws -> String {
        let candidates = try await store.subscriptionCandidates()
        return try XCTUnwrap(candidates.first { $0.displayName.uppercased().contains(name.uppercased()) }?.id)
    }
    /// Confirmed monthly Netflix fixture: seeded, detected, confirmed.
    private func confirmedNetflix(_ store: IngestionStore) async throws {
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        try await store.confirmSubscription(matchKey: try await subscriptionKey(store, named: "Netflix"))
    }
    private func settledEntries(_ store: IngestionStore) async throws -> [ExpenseSnapshot] {
        try await store.recentExpenses(limit: 50).filter { $0.dedupeKey.hasPrefix("settle:") }
    }

    // MARK: - Core behavior

    func test_settle_logsMissedCharges_datedAtDueDates() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 2, "Apr 5 and May 5 fell due (both inside the 60-day horizon)")
        let settled = try await settledEntries(store)
        XCTAssertEqual(Set(settled.map(\.date)), [day(2026, 4, 5), day(2026, 5, 5)])
        XCTAssertTrue(settled.allSatisfy { $0.source == .automatic && $0.amount == 1200 && $0.currencyCode == "ALL" },
                      "Settled entries are auto-marked and carry the subscription's amount and currency")
        XCTAssertTrue(settled.allSatisfy { $0.subscriptionName != nil },
                      "Settled entries are linked to the confirmed subscription")
        XCTAssertTrue(settled.allSatisfy { $0.categoryName != nil },
                      "Settled entries get the merchant-default (or Other) category, never nil")
    }

    func test_settle_isIdempotent() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        _ = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        let countAfterFirst = try await store.expenseCount()
        let secondRun = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(secondRun, 0, "Settled due dates are covered — nothing new to log")
        let countAfterSecond = try await store.expenseCount()
        XCTAssertEqual(countAfterFirst, countAfterSecond)
    }

    func test_weeklyCadence_flowsThroughTheStore() async throws {
        let store = try makeStore()
        for (i, d) in [4, 11, 18, 25].enumerated() {   // four weekly charges in May
            _ = try await store.ingest(NormalizedTransaction(
                externalID: "gym\(i)", amount: 500, currency: .all, date: day(2026, 5, d),
                rawMerchant: "FitGym", kind: .expense, accountRef: "card"), source: .imported)
        }
        _ = try await store.refreshSubscriptions(now: day(2026, 5, 26))
        try await store.confirmSubscription(matchKey: try await subscriptionKey(store, named: "FitGym"))
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 6, 10))
        XCTAssertEqual(created, 2, "Jun 1 and Jun 8 fell due at WEEKLY cadence — a monthly walk would find none")
        let settled = try await settledEntries(store)
        XCTAssertEqual(Set(settled.map(\.date)), [day(2026, 6, 1), day(2026, 6, 8)])
    }

    func test_twoSubscriptions_eachSettlesOnlyItsOwnMerchant() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        for (i, m) in [1, 2, 3].enumerated() {   // Spotify bills the 20th, different amount
            _ = try await store.ingest(NormalizedTransaction(
                externalID: "sp\(i)", amount: 500, currency: .all, date: day(2026, m, 20),
                rawMerchant: "Spotify", kind: .expense, accountRef: "card"), source: .imported)
        }
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 25))
        try await store.confirmSubscription(matchKey: try await subscriptionKey(store, named: "Netflix"))
        try await store.confirmSubscription(matchKey: try await subscriptionKey(store, named: "Spotify"))
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 3)
        let settled = try await settledEntries(store)
        let netflix = settled.filter { $0.amount == 1200 }
        let spotify = settled.filter { $0.amount == 500 }
        XCTAssertEqual(Set(netflix.map(\.date)), [day(2026, 4, 5), day(2026, 5, 5)],
                       "Netflix settles on ITS schedule with ITS amount — never cross-merchant")
        XCTAssertEqual(Set(spotify.map(\.date)), [day(2026, 4, 20)],
                       "Spotify's May 20 due is still in the future at now = May 12")
    }

    // MARK: - Eligibility guards

    func test_settle_skipsUnconfirmed() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        // Detected but never confirmed → no consent → nothing settled.
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 0)
    }

    func test_settle_stopsAfterDismiss() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        try await store.dismissSubscription(matchKey: try await subscriptionKey(store, named: "Netflix"))
        // Dismissing a previously-confirmed sub withdraws consent — the user-visible contract.
        // (dismiss clears isConfirmed too; the sweep's !isDismissed clause is cross-device defense.)
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 0)
    }

    func test_settle_skipsVariableAmount() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store, amounts: [900, 1200, 1500])
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        let key = try await subscriptionKey(store, named: "Netflix")
        let candidates = try await store.subscriptionCandidates()   // local first: XCTUnwrap can't await
        let candidate = try XCTUnwrap(candidates.first { $0.id == key })
        XCTAssertTrue(candidate.isVariableAmount, "Seed must actually exercise the variable-amount guard")
        try await store.confirmSubscription(matchKey: key)
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 0, "Variable-amount subs have no trustworthy amount — never guess")
    }

    func test_settle_skipsSubArchivedAfterAllChargesDeleted() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        let keys = try await store.recentExpenses(limit: 10).map(\.dedupeKey)
        for k in keys { try await store.deleteExpense(dedupeKey: k) }
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))   // confirmed + 0 charges → archived
        // Belt and braces: the archived guard AND the no-real-anchor guard both stop this.
        // Pins the user flow "delete the whole series → the app stops inventing it."
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 0)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 0, "Nothing resurrects over the deleted series")
    }

    func test_sameMerchantTwoConfirmedCadences_settlesNeither() async throws {
        let store = try makeStore()
        for (i, d) in [5, 12, 19, 26].enumerated() {   // weekly era in January
            _ = try await store.ingest(NormalizedTransaction(
                externalID: "w\(i)", amount: 1200, currency: .all, date: day(2026, 1, d),
                rawMerchant: "Netflix", kind: .expense, accountRef: "card"), source: .imported)
        }
        _ = try await store.refreshSubscriptions(now: day(2026, 2, 1))
        try await store.confirmSubscription(matchKey: try await subscriptionKey(store, named: "Netflix"))
        for (i, md) in [(2, 26), (3, 26), (4, 26), (5, 26), (6, 26)].enumerated() {   // series turns monthly
            _ = try await store.ingest(NormalizedTransaction(
                externalID: "m\(i)", amount: 1200, currency: .all, date: day(2026, md.0, md.1),
                rawMerchant: "Netflix", kind: .expense, accountRef: "card"), source: .imported)
        }
        _ = try await store.refreshSubscriptions(now: day(2026, 7, 1))
        let candidates = try await store.subscriptionCandidates()
        let netflixRecords = candidates.filter { $0.displayName.uppercased().contains("NETFLIX") }
        guard netflixRecords.count == 2 else {
            throw XCTSkip("Detector did not produce two same-merchant records (\(netflixRecords.count)) — guard not reachable via public API in this scenario")
        }
        for r in netflixRecords where !r.isConfirmed { try await store.confirmSubscription(matchKey: r.id) }
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 7, 10))
        XCTAssertEqual(created, 0, "Two confirmed schedules for one merchant is ambiguous — guess neither")
    }

    // MARK: - Deletion semantics (the review's HIGH findings)

    func test_deletedSettledEntry_doesNotResurrect() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        _ = try await store.settleDueSubscriptionCharges(now: day(2026, 4, 7))   // settles Apr 5
        let settled = try await settledEntries(store)
        let aprilKey = try XCTUnwrap(settled.first { $0.date == day(2026, 4, 5) }?.dedupeKey)
        try await store.deleteExpense(dedupeKey: aprilKey)
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 4, 7))
        XCTAssertEqual(created, 0, "A deleted settle entry's tombstone covers its due date — deletion is final")
        let after = try await settledEntries(store)
        XCTAssertTrue(after.isEmpty, "The deleted entry must not come back on the next sweep")
    }

    func test_deletingASettleEntry_mutesTheSub_untilNewRealEvidence() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        _ = try await store.settleDueSubscriptionCharges(now: day(2026, 4, 7))   // settles Apr 5
        let settled = try await settledEntries(store)
        let aprilKey = try XCTUnwrap(settled.first?.dedupeKey)
        try await store.deleteExpense(dedupeKey: aprilKey)                        // user: "this didn't happen"
        let whileMuted = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(whileMuted, 0, "Rejecting a guess mutes the sub — May 5 must NOT be fabricated")
        // A real charge arrives (statement import) → the sub is provably alive again.
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "real-may", amount: 1200, currency: .all, date: day(2026, 5, 5),
            rawMerchant: "NETFLIX 4471", kind: .expense, accountRef: "card"), source: .imported)
        let afterEvidence = try await store.settleDueSubscriptionCharges(now: day(2026, 6, 10))
        XCTAssertEqual(afterEvidence, 1, "New real evidence lifts the mute")
        let entries = try await settledEntries(store)
        XCTAssertEqual(entries.map(\.date), [day(2026, 6, 5)])
    }

    // MARK: - Anchoring semantics

    func test_oneOffPurchase_doesNotHijackTheSchedule() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        // A same-merchant one-off (gift card) at a non-subscription amount, mid-cycle.
        _ = try await store.logManual(amount: 5000, currency: .all, merchant: "Netflix",
                                      categoryName: nil, date: day(2026, 3, 20))
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 4, 10))
        XCTAssertEqual(created, 1)
        let settled = try await settledEntries(store)
        XCTAssertEqual(settled.map(\.date), [day(2026, 4, 5)],
                       "The schedule stays anchored on billing-amount evidence (Mar 5), not the Mar 20 one-off")
    }

    func test_priceChangeWithinTolerance_anchorsTheSchedule() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        // The April charge arrives via import at +10% (inside the detector's 15% tolerance).
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "apr", amount: 1320, currency: .all, date: day(2026, 4, 5),
            rawMerchant: "NETFLIX 4471", kind: .expense, accountRef: "card"), source: .imported)
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 10))
        XCTAssertEqual(created, 1, "Only May 5 is missing — Apr 5 is real evidence, not a gap")
        let settled = try await settledEntries(store)
        XCTAssertEqual(settled.map(\.date), [day(2026, 5, 5)])
        XCTAssertEqual(settled.first?.amount, 1200,
                       "Settled amount is the sub's detector amount until a refresh catches the price up (documented)")
    }

    func test_monthEndSchedule_doesNotDriftAcrossRuns() async throws {
        let store = try makeStore()
        for (i, ymd) in [(2025, 11, 30), (2025, 12, 31), (2026, 1, 31)].enumerated() {
            _ = try await store.ingest(NormalizedTransaction(
                externalID: "me\(i)", amount: 1200, currency: .all, date: day(ymd.0, ymd.1, ymd.2),
                rawMerchant: "Netflix", kind: .expense, accountRef: "card"), source: .imported)
        }
        _ = try await store.refreshSubscriptions(now: day(2026, 2, 1))
        try await store.confirmSubscription(matchKey: try await subscriptionKey(store, named: "Netflix"))
        _ = try await store.settleDueSubscriptionCharges(now: day(2026, 3, 5))    // settles Feb 28
        let second = try await store.settleDueSubscriptionCharges(now: day(2026, 4, 2))
        XCTAssertEqual(second, 1)
        let settled = try await settledEntries(store)
        XCTAssertEqual(Set(settled.map(\.date)), [day(2026, 2, 28), day(2026, 3, 31)],
                       "Schedule stays anchored on the REAL Jan 31 charge across runs — Mar 31, never a drifted Mar 28")
    }

    // MARK: - Import reconciliation

    func test_laterStatementImport_mergesIntoSettledEntry_noDuplicate() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        _ = try await store.settleDueSubscriptionCharges(now: day(2026, 4, 7))   // settles Apr 5
        let before = try await store.expenseCount()
        // The bank statement posts the same charge 2 days after the due date.
        let outcome = try await store.ingest(NormalizedTransaction(
            externalID: nil, amount: 1200, currency: .all, date: day(2026, 4, 7),
            rawMerchant: "NETFLIX 4471", kind: .expense, accountRef: "card"), source: .imported)
        XCTAssertEqual(outcome, .merged, "The posting must reconcile into the settled entry")
        let after = try await store.expenseCount()
        XCTAssertEqual(before, after, "Settle + import of the same charge must not double-count")
    }

    func test_earlyStatementPosting_mergesIntoSettledEntry() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        _ = try await store.settleDueSubscriptionCharges(now: day(2026, 4, 7))   // settles Apr 5
        let before = try await store.expenseCount()
        // A 30-day biller posts BEFORE the calendar-month predicted date (review finding):
        // the widened settle-entry window [posting−4, posting+4) must still merge it.
        let outcome = try await store.ingest(NormalizedTransaction(
            externalID: nil, amount: 1200, currency: .all, date: day(2026, 4, 3),
            rawMerchant: "NETFLIX 4471", kind: .expense, accountRef: "card"), source: .imported)
        XCTAssertEqual(outcome, .merged, "A posting 2 days BEFORE the predicted date reconciles into the settle entry")
        let after = try await store.expenseCount()
        XCTAssertEqual(before, after)
    }
}
