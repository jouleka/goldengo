import XCTest
import GoldengoCore
@testable import GoldengoData

final class ImportStatementTests: XCTestCase {
    private func txns() -> [NormalizedTransaction] {
        [ NormalizedTransaction(externalID: "a", amount: 100, currency: .all, date: .now,
                                rawMerchant: "Spar", kind: .expense, accountRef: "statement"),
          NormalizedTransaction(externalID: "b", amount: 200, currency: .all, date: .now,
                                rawMerchant: "Kios", kind: .expense, accountRef: "statement") ]
    }
    func test_import_insertsAll_andRecordsBatch() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let s = try await store.importStatement(txns(), fileName: "may.csv")
        XCTAssertEqual(s.imported, 2)
        XCTAssertEqual(s.deduped, 0)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2)
        let batchCount = try await store.importBatchCount()
        XCTAssertEqual(batchCount, 1)
    }
    func test_reimport_sameRows_allDeduped() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.importStatement(txns(), fileName: "may.csv")
        let s = try await store.importStatement(txns(), fileName: "may-again.csv")
        XCTAssertEqual(s.imported, 0)
        XCTAssertEqual(s.deduped, 2)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2) // no double-count
    }
}
