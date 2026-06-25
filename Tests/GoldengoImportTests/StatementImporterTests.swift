import XCTest
import GoldengoCore
@testable import GoldengoImport

final class StatementImporterTests: XCTestCase {
    func test_csv_routesThroughProfile() {
        let csv = "Date,Description,Amount,Reference\n2026-05-01,SPAR,-100.00,r1\n"
        let txns = StatementImporter.transactions(fromCSV: csv, currency: .all)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns[0].kind, .expense)
    }

    func test_pdfText_routesThroughParser() {
        let text = "NXJERRJE LLOGARIE\nDEBI KREDI PERSHKRIMI\n01/05/26 SPAR 01/05/26 -100.00 900.00\n"
        let txns = StatementImporter.transactions(fromPDFText: text, currency: .all)
        XCTAssertEqual(txns.count, 1)
    }

    // A summary/balance row that happens to carry a date + amount must be skipped, not ingested as
    // a phantom transaction (the PDF path enforces skipRowKeywords; the CSV path must too).
    func test_csv_skipsSummaryRows() {
        let csv = """
        Date,Description,Amount,Reference
        2026-05-01,SPAR,-100.00,r1
        2026-05-31,Closing balance,5000.00,
        """
        let txns = StatementImporter.transactions(fromCSV: csv, currency: .all)
        XCTAssertEqual(txns.count, 1, "The 'Closing balance' summary row must be skipped")
        XCTAssertEqual(txns[0].kind, .expense)
    }
}
