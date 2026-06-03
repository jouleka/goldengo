import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class IngestionStoreTests: XCTestCase {
    private func tx(ext: String?, amount: Decimal, merchant: String, source: ExpenseSource = .imported) -> NormalizedTransaction {
        NormalizedTransaction(externalID: ext, amount: amount, currency: .all,
                              date: Date(timeIntervalSince1970: 1_750_000_000),
                              rawMerchant: merchant, kind: .expense, accountRef: "cash")
    }

    func test_ingest_insertsNewExpense() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let outcome = try await store.ingest(tx(ext: "a1", amount: 500, merchant: "Spar"))
        XCTAssertEqual(outcome, .inserted)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1)
    }

    func test_ingest_sameDedupeKeyMerges_noDoubleCount() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.ingest(tx(ext: "a1", amount: 500, merchant: "Spar"))
        let second = try await store.ingest(tx(ext: "a1", amount: 500, merchant: "Spar"))
        XCTAssertEqual(second, .merged)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1)
    }

    // T1 — merge preserves first-seen amount
    func test_ingest_mergePreservesFirstSeenAmount() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.ingest(tx(ext: "k", amount: 500, merchant: "Spar"))
        let second = try await store.ingest(tx(ext: "k", amount: 999, merchant: "Spar"))
        XCTAssertEqual(second, .merged)
        let snap = try await store.snapshot(dedupeKey: "ext:k")
        XCTAssertEqual(snap?.amount, 500)
    }

    // F2 — a EUR expense now converts INTO the lek total (was excluded under single-currency filtering).
    func test_logManual_eurExpense_convertsIntoLekTotal() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let rates = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1],
                              asOf: Date(timeIntervalSince1970: 1_780_444_800))
        try await store.logManual(amount: 1, currency: .eur, merchant: nil, categoryName: nil)
        let total = try await store.todayTotal(in: .all, rates: rates)   // 1 EUR = 100 ALL
        XCTAssertEqual(total, 100)
    }

    func test_ingest_manualThenImport_mergesAndUpgradesSource() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        // Manual entry with no externalID -> composite key
        let manual = NormalizedTransaction(externalID: nil, amount: 500, currency: .all,
            date: Date(timeIntervalSince1970: 1_750_000_000), rawMerchant: "Spar",
            kind: .expense, accountRef: "cash")
        _ = try await store.ingest(manual, source: .manual)
        // Imported row, same composite key
        let outcome = try await store.ingest(manual, source: .imported)
        XCTAssertEqual(outcome, .merged)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1)
        let snap = try await store.snapshot(dedupeKey: manual.dedupeKey)
        XCTAssertEqual(snap?.source, .imported)   // import upgrades the record's provenance
    }
}
