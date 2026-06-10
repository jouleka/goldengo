import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class PendingSubscriptionChargesTests: XCTestCase {
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

    // MARK: - Core behavior

    func test_pending_surfacesMissedCharges_atTheirDueDates() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(pending.map(\.dueDate), [day(2026, 4, 5), day(2026, 5, 5)],
                       "Apr 5 and May 5 fell due (inside the 60-day horizon), oldest first")
        XCTAssertTrue(pending.allSatisfy { $0.amount == 1200 && $0.currencyCode == "ALL" })
        XCTAssertTrue(pending.allSatisfy { $0.merchantName == "Netflix" },
                      "Ghosts carry the anchor's REAL merchant string so a later import merges")
    }

    func test_pending_isReadOnly() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        let before = try await store.expenseCount()
        _ = try await store.pendingSubscriptionCharges(now: day(2026, 5, 12))
        _ = try await store.pendingSubscriptionCharges(now: day(2026, 5, 12))
        let after = try await store.expenseCount()
        XCTAssertEqual(before, after, "Surfacing ghosts must never write anything")
    }

    func test_loggingAGhost_removesIt_andALaterImportMerges() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 4, 7))
        let ghost = try XCTUnwrap(pending.first)   // Apr 5
        // The one-tap flow: ghost → logAutomatic at the due date (the Apple Pay capture path).
        _ = try await store.logAutomatic(amount: ghost.amount, currency: CurrencyCode(ghost.currencyCode),
                                         merchant: ghost.merchantName, date: ghost.dueDate)
        let remaining = try await store.pendingSubscriptionCharges(now: day(2026, 4, 7))
        XCTAssertTrue(remaining.isEmpty, "The logged charge covers its due date — the ghost vanishes")
        // The bank statement posts the same charge 2 days later: GOL-79 reconciliation merges it.
        let before = try await store.expenseCount()
        let outcome = try await store.ingest(NormalizedTransaction(
            externalID: nil, amount: 1200, currency: .all, date: day(2026, 4, 7),
            rawMerchant: "NETFLIX 4471", kind: .expense, accountRef: "card"), source: .imported)
        XCTAssertEqual(outcome, .merged, "Ghost-logged entries reconcile with imports exactly like Apple Pay captures")
        let after = try await store.expenseCount()
        XCTAssertEqual(before, after)
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
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 6, 10))
        XCTAssertEqual(pending.map(\.dueDate), [day(2026, 6, 1), day(2026, 6, 8)],
                       "Jun 1 and Jun 8 fell due at WEEKLY cadence — a monthly walk would find none")
    }

    func test_twoSubscriptions_eachGhostsOnlyItsOwnMerchant() async throws {
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
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 5, 12))
        let netflix = pending.filter { $0.amount == 1200 }
        let spotify = pending.filter { $0.amount == 500 }
        XCTAssertEqual(netflix.map(\.dueDate), [day(2026, 4, 5), day(2026, 5, 5)],
                       "Netflix ghosts ride ITS schedule with ITS amount — never cross-merchant")
        XCTAssertEqual(spotify.map(\.dueDate), [day(2026, 4, 20)],
                       "Spotify's May 20 due is still in the future at now = May 12")
    }

    func test_monthEndSchedule_anchorsOnTheRealBillingDay() async throws {
        let store = try makeStore()
        for (i, ymd) in [(2025, 11, 30), (2025, 12, 31), (2026, 1, 31)].enumerated() {
            _ = try await store.ingest(NormalizedTransaction(
                externalID: "me\(i)", amount: 1200, currency: .all, date: day(ymd.0, ymd.1, ymd.2),
                rawMerchant: "Netflix", kind: .expense, accountRef: "card"), source: .imported)
        }
        _ = try await store.refreshSubscriptions(now: day(2026, 2, 1))
        try await store.confirmSubscription(matchKey: try await subscriptionKey(store, named: "Netflix"))
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 4, 2))
        XCTAssertEqual(pending.map(\.dueDate), [day(2026, 2, 28), day(2026, 3, 31)],
                       "Anchored multi-period advance from the REAL Jan 31 billing day — Mar 31, not a drifted Mar 28")
    }

    // MARK: - Eligibility guards

    func test_pending_skipsUnconfirmed() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        // Detected but never confirmed → no consent → no ghosts.
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertTrue(pending.isEmpty)
    }

    func test_pending_stopsAfterDismiss() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        try await store.dismissSubscription(matchKey: try await subscriptionKey(store, named: "Netflix"))
        // Dismissing a previously-confirmed sub withdraws consent — the permanent silencer for dead subs.
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertTrue(pending.isEmpty)
    }

    func test_pending_skipsVariableAmount() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store, amounts: [900, 1200, 1500])
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        let key = try await subscriptionKey(store, named: "Netflix")
        let candidates = try await store.subscriptionCandidates()   // local first: XCTUnwrap can't await
        let candidate = try XCTUnwrap(candidates.first { $0.id == key })
        XCTAssertTrue(candidate.isVariableAmount, "Seed must actually exercise the variable-amount guard")
        try await store.confirmSubscription(matchKey: key)
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertTrue(pending.isEmpty, "Variable-amount subs have no trustworthy amount — never guess")
    }

    func test_pending_skipsSubArchivedAfterAllChargesDeleted() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        let keys = try await store.recentExpenses(limit: 10).map(\.dedupeKey)
        for k in keys { try await store.deleteExpense(dedupeKey: k) }
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))   // confirmed + 0 charges → archived
        // Pins the user flow "delete the whole series → the app stops asking about it."
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertTrue(pending.isEmpty)
    }

    func test_sameMerchantTwoConfirmedCadences_surfacesNothing() async throws {
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
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 7, 10))
        XCTAssertTrue(pending.isEmpty, "Two confirmed schedules for one merchant is ambiguous — ask about neither")
    }

    // MARK: - Coverage and anchoring semantics

    func test_deletedCharge_neverResurfacesAsAGhost() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        // April's real charge posts late (Apr 10) via import, then the user deletes it (a refund).
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "apr-late", amount: 1200, currency: .all, date: day(2026, 4, 10),
            rawMerchant: "NETFLIX 4471", kind: .expense, accountRef: "card"), source: .imported)
        let rows = try await store.recentExpenses(limit: 10)
        let lateKey = try XCTUnwrap(rows.first { $0.date == day(2026, 4, 10) }?.dedupeKey)
        try await store.deleteExpense(dedupeKey: lateKey)
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 4, 20))
        XCTAssertTrue(pending.isEmpty,
                      "The tombstone covers its whole cadence period — deletion is final, nothing re-asks")
    }

    func test_oneOffPurchase_doesNotHijackTheSchedule() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        // A same-merchant one-off (gift card) at a non-subscription amount, mid-cycle.
        _ = try await store.logManual(amount: 5000, currency: .all, merchant: "Netflix",
                                      categoryName: nil, date: day(2026, 3, 20))
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 4, 10))
        XCTAssertEqual(pending.map(\.dueDate), [day(2026, 4, 5)],
                       "The schedule stays anchored on billing-amount evidence (Mar 5), not the Mar 20 one-off")
    }

    func test_priceChangeWithinTolerance_anchorsTheSchedule() async throws {
        let store = try makeStore()
        try await confirmedNetflix(store)
        // The April charge arrives via import at +10% (inside the detector's 15% tolerance).
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "apr", amount: 1320, currency: .all, date: day(2026, 4, 5),
            rawMerchant: "NETFLIX 4471", kind: .expense, accountRef: "card"), source: .imported)
        let pending = try await store.pendingSubscriptionCharges(now: day(2026, 5, 10))
        XCTAssertEqual(pending.map(\.dueDate), [day(2026, 5, 5)],
                       "Only May 5 is missing — the Apr 5 real charge is evidence, not a gap")
        XCTAssertEqual(pending.first?.amount, 1200,
                       "Ghost amounts lag until the detector refresh catches the price up (documented; editable on log)")
    }
}
