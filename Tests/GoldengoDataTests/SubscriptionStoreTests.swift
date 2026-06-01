import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class SubscriptionStoreTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    private func makeStore() throws -> IngestionStore {
        IngestionStore(modelContainer: try ModelContainer.goldengoInMemory())
    }

    private func seedMonthlyNetflix(_ store: IngestionStore) async throws {
        for (i, m) in [1, 2, 3].enumerated() {
            _ = try await store.ingest(
                NormalizedTransaction(externalID: "nf\(i)", amount: Decimal(9.99), currency: .all,
                                      date: day(2026, m, 5), rawMerchant: "Netflix",
                                      kind: .expense, accountRef: "card"), source: .imported)
        }
    }

    func test_refreshCreatesCandidate() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        let count = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        XCTAssertEqual(count, 1)
        let cands = try await store.subscriptionCandidates()
        XCTAssertEqual(cands.count, 1)
        XCTAssertEqual(cands[0].cadence, .monthly)
        XCTAssertEqual(cands[0].displayName, "Netflix")
    }

    func test_confirmIsPreservedAcrossRefresh() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        let key = try await store.subscriptionCandidates()[0].id
        try await store.confirmSubscription(matchKey: key)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 11))
        let after = try await store.subscriptionCandidates().first { $0.id == key }
        XCTAssertEqual(after?.isConfirmed, true)
    }

    func test_dismissedCandidatesAreNotResurfaced() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        let key = try await store.subscriptionCandidates()[0].id
        try await store.dismissSubscription(matchKey: key)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 11))
        let cands = try await store.subscriptionCandidates()
        XCTAssertTrue(cands.isEmpty)
    }

    func test_refreshIsIdempotent_noDuplicateRecords() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 11))
        let recordCount = try await store.subscriptionRecordCount()
        XCTAssertEqual(recordCount, 1)
    }

    func test_duplicateMatchKeysConvergeOnRefresh_noCrash() async throws {
        // Simulate a CloudKit cross-device duplicate: two SubscriptionRecords share a matchKey.
        // refreshSubscriptions must NOT trap and must converge to a single active candidate.
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        let key = try await store.subscriptionCandidates()[0].id

        let ctx = ModelContext(store.modelContainer)   // @ModelActor exposes nonisolated modelContainer
        ctx.insert(SubscriptionRecord(matchKey: key, displayName: "Netflix dup", cadence: .monthly))
        try ctx.save()
        let dupRecordCount = try await store.subscriptionRecordCount()
        XCTAssertEqual(dupRecordCount, 2)

        _ = try await store.refreshSubscriptions(now: day(2026, 3, 11))   // must not crash
        let active = try await store.subscriptionCandidates().filter { $0.id == key }
        XCTAssertEqual(active.count, 1)   // converged: one archived, one active
    }
}
