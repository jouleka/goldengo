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
        await m.importCSV(text: bigText, fileName: "huge.csv")
        XCTAssertEqual(m.resultText, "File too large (max 10 MB).")
        XCTAssertTrue(m.result.isFailure, "An error must be marked a failure (so the UI shows a warning, not a green check).")
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
        await m.importCSV(text: csv, fileName: "sample.csv")
        XCTAssertEqual(m.resultText, "Imported 2, skipped 0 duplicates")
        XCTAssertFalse(m.result.isFailure, "A successful import must NOT be marked a failure.")
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2)
    }

    func test_importPDF_oversizedFile_setsErrorAndImportsNothing() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let m = ImportModel(store: store, currency: .all)
        // Write an ~11 MB junk file to a temp .pdf URL
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let junk = Data(count: 11_000_000)
        try junk.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        await m.importPDF(url: tmp, fileName: "huge.pdf")
        XCTAssertTrue(m.resultText.contains("too large"), "Expected 'too large' in resultText, got: \(m.resultText)")
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 0)
    }

    func test_importPDF_fromSyntheticFixture() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let m = ImportModel(store: store, currency: .all)
        let url = try XCTUnwrap(Bundle.module.url(forResource: "synthetic-statement", withExtension: "pdf"))
        await m.importPDF(url: url, fileName: "synthetic-statement.pdf")
        let count = try await store.expenseCount()
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    // GOL-79: the single file-open entry point used by both the picker and Share-to-Goldengo.
    func test_importFile_csv_importsRows() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let m = ImportModel(store: store, currency: .all)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gol79-\(UUID().uuidString).csv")
        let csv = """
        Date,Description,Amount,Reference
        2026-05-30,SPAR TIRANA,-1500.00,tx1
        """
        try csv.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        await m.importFile(url: url)

        XCTAssertEqual(m.resultText, "Imported 1, skipped 0 duplicates")
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1)
    }

    func test_importFile_tooLarge_reportsError() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let m = ImportModel(store: store, currency: .all)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gol79-big-\(UUID().uuidString).csv")
        try Data(count: 10_000_001).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await m.importFile(url: url)

        XCTAssertEqual(m.resultText, "File too large (max 10 MB).")
    }
}
