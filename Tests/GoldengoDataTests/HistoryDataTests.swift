import XCTest
import GoldengoCore
@testable import GoldengoData

/// `historyData` is what the History browser fetches per period. The contracts that matter to a user:
/// the period boundary is half-open (a row at the first instant of next month is NOT this month's),
/// the headline total counts spending only (income/transfers don't inflate it) and converts currency,
/// and the row list is newest-first across all kinds.
final class HistoryDataTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }
    private let rates = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1],
                                  asOf: Date(timeIntervalSince1970: 1_780_444_800))

    private func ingest(_ store: IngestionStore, _ id: String, _ amount: Double, _ date: Date,
                        currency: CurrencyCode = .all, kind: TransactionKind = .expense) async throws {
        _ = try await store.ingest(NormalizedTransaction(externalID: id, amount: Decimal(amount), currency: currency,
            date: date, rawMerchant: "M-\(id)", kind: kind, accountRef: "card"), source: .imported)
    }

    func test_periodBoundary_isHalfOpen() async throws {
        let store = try makeStore()
        try await ingest(store, "at-start", 10, day(2026, 6, 1))    // == range.start → included
        try await ingest(store, "mid", 10, day(2026, 6, 15))        // included
        try await ingest(store, "at-end", 10, day(2026, 7, 1))      // == range.end → next month, excluded
        try await ingest(store, "prev", 10, day(2026, 5, 31))       // previous month, excluded

        let snap = try await store.historyData(scale: .month, anchor: day(2026, 6, 15),
                                               displayCurrency: .all, rates: rates,
                                               now: day(2026, 6, 26), calendar: cal)
        let keys = Set(snap.rows.map(\.merchantName))
        XCTAssertEqual(snap.rows.count, 2)
        XCTAssertTrue(keys.contains("M-at-start"), "the first instant of the month is inside it")
        XCTAssertTrue(keys.contains("M-mid"))
        XCTAssertFalse(keys.contains("M-at-end"), "the first instant of next month belongs to next month")
        XCTAssertFalse(keys.contains("M-prev"))
    }

    func test_totalSpent_countsExpensesOnly_andConvertsCurrency() async throws {
        let store = try makeStore()
        try await ingest(store, "lek", 100, day(2026, 6, 10), currency: .all, kind: .expense)   // 100 ALL
        try await ingest(store, "eur", 2, day(2026, 6, 11), currency: .eur, kind: .expense)     // 2 EUR = 200 ALL
        try await ingest(store, "pay", 5000, day(2026, 6, 12), currency: .all, kind: .income)   // income — must NOT count

        let snap = try await store.historyData(scale: .month, anchor: day(2026, 6, 15),
                                               displayCurrency: .all, rates: rates,
                                               now: day(2026, 6, 26), calendar: cal)
        XCTAssertEqual(snap.totalSpent, 300, "spend only, converted to display currency — income excluded")
        XCTAssertEqual(snap.expenseCount, 2, "two expenses; the income isn't an expense")
        XCTAssertEqual(snap.rows.count, 3, "but all three rows are shown in the list")
        XCTAssertEqual(snap.ratesAsOf, rates.asOf, "a EUR→ALL conversion happened")
    }

    func test_emptyPeriod_isZeroes() async throws {
        let store = try makeStore()
        try await ingest(store, "may", 10, day(2026, 5, 10))
        let snap = try await store.historyData(scale: .month, anchor: day(2026, 6, 15),
                                               displayCurrency: .all, rates: rates,
                                               now: day(2026, 6, 26), calendar: cal)
        XCTAssertEqual(snap.totalSpent, 0)
        XCTAssertEqual(snap.expenseCount, 0)
        XCTAssertTrue(snap.rows.isEmpty)
    }

    func test_investmentRowRemainsVisible_butIsNotCountedAsSpent() async throws {
        let store = try makeStore()
        try await store.logManual(amount: 2_000, currency: .all, merchant: "Broker",
                                  categoryName: "Stocks", date: day(2026, 6, 10))

        let snap = try await store.historyData(scale: .month, anchor: day(2026, 6, 15),
                                               displayCurrency: .all, rates: rates,
                                               now: day(2026, 6, 26), calendar: cal)
        XCTAssertEqual(snap.totalSpent, 0)
        XCTAssertEqual(snap.expenseCount, 0)
        XCTAssertEqual(snap.rows.map(\.merchantName), ["Broker"])
    }

    func test_rows_areNewestFirst() async throws {
        let store = try makeStore()
        try await ingest(store, "older", 10, day(2026, 6, 3))
        try await ingest(store, "newer", 10, day(2026, 6, 20))
        let snap = try await store.historyData(scale: .month, anchor: day(2026, 6, 15),
                                               displayCurrency: .all, rates: rates,
                                               now: day(2026, 6, 26), calendar: cal)
        XCTAssertEqual(snap.rows.first?.merchantName, "M-newer")
        XCTAssertEqual(snap.rows.last?.merchantName, "M-older")
    }
}
