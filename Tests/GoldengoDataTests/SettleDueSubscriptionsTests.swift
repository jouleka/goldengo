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
    private func netflixKey(_ store: IngestionStore) async throws -> String {
        let candidates = try await store.subscriptionCandidates()
        return try XCTUnwrap(candidates.first { $0.displayName.uppercased().contains("NETFLIX") }?.id)
    }

    func test_settle_logsMissedCharges_datedAtDueDates() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        try await store.confirmSubscription(matchKey: try await netflixKey(store))
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 2, "Apr 5 and May 5 fell due (both inside the 60-day horizon)")
        let auto = try await store.recentExpenses(limit: 20).filter { $0.source == .automatic }
        XCTAssertEqual(Set(auto.map(\.date)), [day(2026, 4, 5), day(2026, 5, 5)])
        XCTAssertTrue(auto.allSatisfy { $0.amount == 1200 && $0.currencyCode == "ALL" },
                      "Settled entries carry the subscription's amount and currency")
        XCTAssertTrue(auto.allSatisfy { $0.subscriptionName != nil },
                      "Settled entries are linked to the confirmed subscription")
    }

    func test_settle_isIdempotent() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        try await store.confirmSubscription(matchKey: try await netflixKey(store))
        _ = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        let countAfterFirst = try await store.expenseCount()
        let secondRun = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(secondRun, 0, "The settled entries are now the last observed charges — nothing due")
        let countAfterSecond = try await store.expenseCount()
        XCTAssertEqual(countAfterFirst, countAfterSecond)
    }

    func test_settle_skipsUnconfirmed() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        // Detected but never confirmed → no consent → nothing settled.
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 0)
    }

    func test_settle_skipsDismissed() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        try await store.dismissSubscription(matchKey: try await netflixKey(store))
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 0)
    }

    func test_settle_skipsVariableAmount() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store, amounts: [900, 1200, 1500])
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        let key = try await netflixKey(store)
        let candidates = try await store.subscriptionCandidates()   // local first: XCTUnwrap can't await
        let candidate = try XCTUnwrap(candidates.first { $0.id == key })
        XCTAssertTrue(candidate.isVariableAmount, "Seed must actually exercise the variable-amount guard")
        try await store.confirmSubscription(matchKey: key)
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 0, "Variable-amount subs have no trustworthy amount — never guess")
    }
}
