import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class ReconcileImportTests: XCTestCase {
    /// An imported statement row, posting `daysAfterNow` days from now.
    private func importedRow(amount: Decimal, merchant: String, currency: CurrencyCode = .all,
                             daysAfterNow: Int) -> NormalizedTransaction {
        NormalizedTransaction(externalID: nil, amount: amount, currency: currency,
                              date: Date().addingTimeInterval(Double(daysAfterNow) * 86_400),
                              rawMerchant: merchant, kind: .expense, accountRef: nil)
    }

    func test_highConfidence_importMergesIntoAutomatic_noDoubleCount() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 1500, currency: .all, merchant: "Spar")   // swipe ~ now
        // Statement row: "SPAR 4471" → numeric token dropped → normalizes to "SPAR" → matches "Spar".
        let outcome = try await store.ingest(importedRow(amount: 1500, merchant: "SPAR 4471", daysAfterNow: 2),
                                             source: .imported)
        XCTAssertEqual(outcome, .merged)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1, "Same purchase from two paths must collapse to one.")
    }

    func test_locationWordDifference_staysDuplicate() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 1500, currency: .all, merchant: "Spar")
        // "SPAR TIRANA" keeps the location word → "SPAR TIRANA" != "SPAR" → not high-confidence.
        let outcome = try await store.ingest(importedRow(amount: 1500, merchant: "SPAR TIRANA", daysAfterNow: 1),
                                             source: .imported)
        XCTAssertEqual(outcome, .inserted)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2, "A deletable duplicate beats a wrong merge.")
    }

    func test_recurringSameAmount_neverHidesAnExpense() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 300, currency: .all, merchant: "Coffee")
        _ = try await store.logAutomatic(amount: 300, currency: .all, merchant: "Coffee")
        // One coffee on the statement merges into AT MOST one automatic entry; the other survives.
        _ = try await store.ingest(importedRow(amount: 300, merchant: "Coffee", daysAfterNow: 1), source: .imported)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2,
                       "Two distinct taps + one statement row = two records; never collapse a real expense away.")
    }

    func test_neverMergesIntoManual() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logManual(amount: 1500, currency: .all, merchant: "Spar", categoryName: nil)
        let outcome = try await store.ingest(importedRow(amount: 1500, merchant: "SPAR 4471", daysAfterNow: 1),
                                             source: .imported)
        XCTAssertEqual(outcome, .inserted)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2, "Hand-typed entries are user truth; never reconciled away.")
    }

    func test_currencyMismatch_doesNotMerge() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 10, currency: .eur, merchant: "Spar")
        let outcome = try await store.ingest(importedRow(amount: 10, merchant: "SPAR 4471", currency: .all, daysAfterNow: 1),
                                             source: .imported)
        XCTAssertEqual(outcome, .inserted)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2, "Same number, different currency = different money.")
    }

    func test_outsideDateWindow_doesNotMerge() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 1500, currency: .all, merchant: "Spar")   // swipe ~ now
        // Posting 6 days after swipe (> swipe+4) → implausible same purchase → kept duplicate.
        let outcome = try await store.ingest(importedRow(amount: 1500, merchant: "SPAR 4471", daysAfterNow: 6),
                                             source: .imported)
        XCTAssertEqual(outcome, .inserted)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2)
    }

    func test_twoStatementRows_reconcileToDistinctCaptures_collapseToTwo() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 300, currency: .all, merchant: "Coffee")
        _ = try await store.logAutomatic(amount: 300, currency: .all, merchant: "Coffee")
        // A real statement has BOTH coffees as rows; each must reconcile into a DIFFERENT capture
        // (one-to-one), not pile onto the first — otherwise the second tap would be hidden.
        let summary = try await store.importStatement(
            [importedRow(amount: 300, merchant: "Coffee", daysAfterNow: 1),
             importedRow(amount: 300, merchant: "Coffee", daysAfterNow: 1)],
            fileName: "two-coffees.csv")
        XCTAssertEqual(summary.deduped, 2, "Both rows reconcile into the two existing captures.")
        XCTAssertEqual(summary.imported, 0)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2, "Two taps + two statement rows collapse to exactly two records.")
    }
}
