import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class ImportModelTests: XCTestCase {
    func test_importCSV_oversizedInput_setsErrorAndImportsNothing() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let m = ImportModel(store: store, currency: .all)
        let bigText = String(repeating: "a,b\n", count: 3_000_000)
        try await m.importCSV(text: bigText, fileName: "huge.csv")
        XCTAssertEqual(m.resultText, "File too large (max 10 MB).")
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 0)
    }

    func test_importCSVText_parsesDetectsAndPersists() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let m = ImportModel(store: store, currency: .all)
        // Uses StatementProfile.generic: yyyy-MM-dd dates, dot-decimal, comma-grouping
        let csv = """
        Date,Description,Amount,Reference
        2026-05-30,SPAR TIRANA,-1500.00,tx1
        2026-05-29,COFFEE,-250.00,tx2
        """
        try await m.importCSV(text: csv, fileName: "sample.csv")
        XCTAssertEqual(m.resultText, "Imported 2, skipped 0 duplicates")
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2)
    }

    func test_importPDF_fromSyntheticFixture() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let m = ImportModel(store: store, currency: .all)
        let url = try XCTUnwrap(Bundle.module.url(forResource: "synthetic-statement", withExtension: "pdf"))
        try await m.importPDF(url: url, fileName: "synthetic-statement.pdf")
        let count = try await store.expenseCount()
        XCTAssertGreaterThanOrEqual(count, 1)
    }
}
