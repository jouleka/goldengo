import XCTest
import GoldengoCore
@testable import GoldengoImport

final class RaiffeisenAlbaniaParserTests: XCTestCase {
    let text = """
    NXJERRJE LLOGARIE
    DATA E TRANSAKSIONIT PERSHKRIMI DATE VALUTA DEBI KREDI BALANCA
    Balanca e Fillimit 1,000.00
    01/05/26 TEST MARKET TIRANA 01/05/26 -100.00 900.00
    02/05/26 TEST SALARY 02/05/26 5,000.00 5,900.00
    Numri i veprimeve ne debi 1 -100.00
    """

    func test_evilLine_doesNotHang() {
        // A line starting with a date then thousands of spaces would backtrack catastrophically
        // without the length guard. This must return instantly.
        let evil = "01/01/01 " + String(repeating: " ", count: 5000)
        let txns = RaiffeisenAlbaniaParser().parse(evil, currency: .all)
        XCTAssertEqual(txns.count, 0)
    }

    func test_parses_transactions_skippingSummaries() {
        let p = RaiffeisenAlbaniaParser()
        XCTAssertTrue(p.canParse(text))
        let txns = p.parse(text, currency: .all)
        XCTAssertEqual(txns.count, 2)
        XCTAssertEqual(txns[0].kind, .expense); XCTAssertEqual(txns[0].amount, 100)
        XCTAssertEqual(txns[1].kind, .income);  XCTAssertEqual(txns[1].amount, 5000)
        XCTAssertEqual(txns[0].rawMerchant, "TEST MARKET TIRANA")
    }
}
