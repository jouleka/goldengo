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
}
