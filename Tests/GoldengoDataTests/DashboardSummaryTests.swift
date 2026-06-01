import XCTest
import GoldengoCore
@testable import GoldengoData

final class DashboardSummaryTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    private func ingest(_ store: IngestionStore, _ id: String, _ amount: Double, _ date: Date, merchant: String, kind: TransactionKind = .expense) async throws {
        _ = try await store.ingest(NormalizedTransaction(externalID: id, amount: Decimal(amount), currency: .all,
            date: date, rawMerchant: merchant, kind: kind, accountRef: "card"), source: .imported)
    }

    func test_monthTotal_countsOnlyCurrentMonthExpenses() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        try await ingest(store, "a", 1000, day(2026, 6, 2), merchant: "Spar")   // this month
        try await ingest(store, "b", 500, day(2026, 6, 10), merchant: "Conad")  // this month
        try await ingest(store, "c", 9999, day(2026, 5, 30), merchant: "Old")    // last month — excluded
        try await ingest(store, "d", 7777, day(2026, 6, 5), merchant: "Pay", kind: .income) // income — excluded
        let s = try await store.dashboardSummary(now: now)
        XCTAssertEqual(s.monthTotal, 1500)
    }

    func test_topCategories_sortedDescending() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        // No merchant→category mapping, so category is nil → "Uncategorized"; group by amount instead via 2 merchants.
        try await ingest(store, "a", 300, day(2026, 6, 2), merchant: "Coffee Corner")
        try await ingest(store, "b", 1200, day(2026, 6, 3), merchant: "Spar Market")
        let s = try await store.dashboardSummary(now: now)
        XCTAssertFalse(s.topCategories.isEmpty)
        // Sorted by total desc.
        XCTAssertEqual(s.topCategories, s.topCategories.sorted { $0.total >= $1.total })
        XCTAssertEqual(s.topCategories.reduce(Decimal(0)) { $0 + $1.total }, 1500)
    }

    func test_monthTotal_isCurrencyIsolated() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        try await ingest(store, "all1", 1000, day(2026, 6, 2), merchant: "Spar")            // ALL
        _ = try await store.ingest(NormalizedTransaction(externalID: "eur1", amount: 50, currency: CurrencyCode("EUR"),
            date: day(2026, 6, 3), rawMerchant: "Amazon", kind: .expense, accountRef: "card"), source: .imported) // EUR
        let s = try await store.dashboardSummary(in: .all, now: now)
        XCTAssertEqual(s.monthTotal, 1000)   // EUR charge excluded from the ALL total
        XCTAssertEqual(s.topCategories.reduce(Decimal(0)) { $0 + $1.total }, 1000)  // categories also currency-isolated
    }

    func test_confirmedSubscriptionsMonthlyEquivalent() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        // Build a confirmed monthly Netflix (1200) via detection + confirm.
        for m in [3, 4, 5] { try await ingest(store, "nf\(m)", 1200, day(2026, m, 5), merchant: "Netflix") }
        _ = try await store.refreshSubscriptions(now: day(2026, 5, 10))
        let cands = try await store.subscriptionCandidates()
        let key = try XCTUnwrap(cands.first?.id)
        try await store.confirmSubscription(matchKey: key)
        let s = try await store.dashboardSummary(now: now)
        XCTAssertEqual(s.confirmedSubscriptionCount, 1)
        XCTAssertEqual(s.confirmedSubscriptionsMonthly, 1200)   // monthly cadence → ×1
    }
}
