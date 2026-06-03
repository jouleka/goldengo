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

    // 1 USD = 100 ALL = 1 EUR, so 1 EUR = 100 ALL.
    private let rates = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1],
                                  asOf: Date(timeIntervalSince1970: 1_780_444_800))

    func test_monthTotal_convertsMixedCurrenciesToDisplayCurrency() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        try await store.logManual(amount: 100, currency: .all, merchant: "Lek buy", categoryName: nil)   // 100 ALL
        try await store.logManual(amount: 2, currency: .eur, merchant: "Euro buy", categoryName: nil)     // 2 EUR = 200 ALL
        let inLek = try await store.dashboardSummary(in: .all, rates: rates, now: now)
        XCTAssertEqual(inLek.monthTotal, 300)             // 100 + 200
        XCTAssertEqual(inLek.ratesAsOf, rates.asOf)        // conversion happened → staleness date present
        let inEur = try await store.dashboardSummary(in: .eur, rates: rates, now: now)
        XCTAssertEqual(inEur.monthTotal, 3)               // 1 (100 ALL) + 2 EUR
    }

    func test_ratesAsOf_isNil_whenNoConversionNeeded() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        try await store.logManual(amount: 100, currency: .all, merchant: "Lek", categoryName: nil)
        let s = try await store.dashboardSummary(in: .all, rates: rates, now: now)
        XCTAssertNil(s.ratesAsOf)                          // all expenses already in display currency
    }

    func test_monthTotal_countsOnlyCurrentMonthExpenses() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        try await ingest(store, "a", 1000, day(2026, 6, 2), merchant: "Spar")   // this month
        try await ingest(store, "b", 500, day(2026, 6, 10), merchant: "Conad")  // this month
        try await ingest(store, "c", 9999, day(2026, 5, 30), merchant: "Old")    // last month — excluded
        try await ingest(store, "d", 7777, day(2026, 6, 5), merchant: "Pay", kind: .income) // income — excluded
        let s = try await store.dashboardSummary(rates: rates, now: now)
        XCTAssertEqual(s.monthTotal, 1500)
    }

    func test_topCategories_sortedDescending() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        // No merchant→category mapping, so imported expenses fall back to "Other"; group by amount via 2 merchants.
        try await ingest(store, "a", 300, day(2026, 6, 2), merchant: "Coffee Corner")
        try await ingest(store, "b", 1200, day(2026, 6, 3), merchant: "Spar Market")
        let s = try await store.dashboardSummary(rates: rates, now: now)
        XCTAssertFalse(s.topCategories.isEmpty)
        // Sorted by total desc.
        XCTAssertEqual(s.topCategories, s.topCategories.sorted { $0.total >= $1.total })
        XCTAssertEqual(s.topCategories.reduce(Decimal(0)) { $0 + $1.total }, 1500)
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
        let s = try await store.dashboardSummary(rates: rates, now: now)
        XCTAssertEqual(s.confirmedSubscriptionCount, 1)
        XCTAssertEqual(s.confirmedSubscriptionsMonthly, 1200)   // monthly cadence → ×1
    }

    // GOL-69: a euro-billed subscription is detected in euro and its monthly estimate converts into
    // the display currency for the Home "~/mo" figure.
    func test_confirmedSubscriptions_convertToDisplayCurrency() async throws {
        let store = try makeStore()
        let now = day(2026, 6, 15)
        // Three monthly €2 charges → a confirmed EUR monthly subscription.
        for m in [3, 4, 5] {
            _ = try await store.ingest(NormalizedTransaction(externalID: "eur\(m)", amount: 2, currency: CurrencyCode("EUR"),
                date: day(2026, m, 5), rawMerchant: "Spotify", kind: .expense, accountRef: "card"), source: .imported)
        }
        _ = try await store.refreshSubscriptions(now: day(2026, 5, 10))
        let cands = try await store.subscriptionCandidates()
        let key = try XCTUnwrap(cands.first?.id)
        try await store.confirmSubscription(matchKey: key)
        // Displayed in lek: €2/mo → L200/mo (1 EUR = 100 ALL), and the staleness date is present.
        let s = try await store.dashboardSummary(in: .all, rates: rates, now: now)
        XCTAssertEqual(s.confirmedSubscriptionsMonthly, 200)
        XCTAssertEqual(s.ratesAsOf, rates.asOf)
    }
}
