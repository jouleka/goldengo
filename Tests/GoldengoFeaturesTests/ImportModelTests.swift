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
        let csv = """
        Date,Amount,Description,Reference
        30.05.2026,"-1.500,00",SPAR TIRANA,tx1
        29.05.2026,"-250,00",COFFEE,tx2
        """
        try await m.importCSV(text: csv, fileName: "sample.csv")
        XCTAssertEqual(m.resultText, "Imported 2, skipped 0 duplicates")
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2)
    }
}
