import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class SubscriptionAutoMatchTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    private func seedMonthlyNetflix(_ store: IngestionStore) async throws {
        for (i, m) in [1, 2, 3].enumerated() {
            _ = try await store.ingest(NormalizedTransaction(
                externalID: "nf\(i)", amount: 1200, currency: .all, date: day(2026, m, 5),
                rawMerchant: "Netflix", kind: .expense, accountRef: "card"), source: .imported)
        }
    }
    private func netflixKey(_ store: IngestionStore) async throws -> String {
        let candidates = try await store.subscriptionCandidates()
        return try XCTUnwrap(candidates.first { $0.displayName.uppercased().contains("NETFLIX") }?.id)
    }
    // Number of recent expenses linked to a subscription with the given display name.
    private func linkedCount(_ store: IngestionStore, name: String) async throws -> Int {
        try await store.recentExpenses(limit: 100).filter { $0.subscriptionName?.uppercased().contains(name.uppercased()) == true }.count
    }

    func test_confirm_backfillsExistingMatchingCharges() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        // Before confirming, nothing is linked.
        let before = try await linkedCount(store, name: "Netflix")
        XCTAssertEqual(before, 0)
        try await store.confirmSubscription(matchKey: try await netflixKey(store))
        // After confirming, the 3 existing Netflix charges are linked.
        let after = try await linkedCount(store, name: "Netflix")
        XCTAssertEqual(after, 3)
    }

    func test_ingestAfterConfirm_linksNewCharge() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        try await store.confirmSubscription(matchKey: try await netflixKey(store))
        // A new Netflix charge arrives and is auto-linked on ingest.
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "nf3", amount: 1200, currency: .all, date: day(2026, 4, 5),
            rawMerchant: "NETFLIX 4471", kind: .expense, accountRef: "card"), source: .imported)
        let linked = try await linkedCount(store, name: "Netflix")
        XCTAssertEqual(linked, 4)
    }

    func test_nonMatchingAndUnconfirmed_notLinked() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        // A one-off non-Netflix charge.
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "x1", amount: 500, currency: .all, date: day(2026, 3, 6),
            rawMerchant: "Spar Market", kind: .expense, accountRef: "card"), source: .imported)
        // Nothing confirmed yet → nothing linked.
        let netflixBefore = try await linkedCount(store, name: "Netflix")
        XCTAssertEqual(netflixBefore, 0)
        // Confirm Netflix; Spar still must not link to it.
        try await store.confirmSubscription(matchKey: try await netflixKey(store))
        let sparLinked = try await linkedCount(store, name: "Spar")
        XCTAssertEqual(sparLinked, 0)
    }

    func test_differentCurrency_notLinked() async throws {
        // A same-merchant charge in a DIFFERENT currency must not link to the ALL subscription.
        let store = try makeStore()
        try await seedMonthlyNetflix(store)   // ALL
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        try await store.confirmSubscription(matchKey: try await netflixKey(store))
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "eur1", amount: 10, currency: CurrencyCode("EUR"), date: day(2026, 4, 5),
            rawMerchant: "Netflix", kind: .expense, accountRef: "card"), source: .imported)
        // Only the 3 ALL charges are linked; the EUR charge is not.
        let linked = try await linkedCount(store, name: "Netflix")
        XCTAssertEqual(linked, 3)
    }
}
