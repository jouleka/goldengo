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

    // T4 — field-level assertions for debit and credit rows
    func test_debitRow_fields() {
        let txns = RaiffeisenAlbaniaParser().parse(text, currency: .all)
        let debit = txns[0]
        XCTAssertEqual(debit.amount, 100)
        XCTAssertEqual(debit.kind, .expense)
        // date: 01/05/26 in UTC → verify year/month/day
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: debit.date)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day, 1)
    }

    func test_creditRow_isIncome() {
        let txns = RaiffeisenAlbaniaParser().parse(text, currency: .all)
        let credit = txns[1]
        XCTAssertEqual(credit.kind, .income)
        XCTAssertEqual(credit.amount, 5000)
    }

    // Real Raiffeisen rows where the description is on a SEPARATE line, so the transaction
    // line is `<txnDate> <valueDate> <amount> <balance>` with no inline description.
    // These were silently dropped before the description became optional.
    func test_parses_rowsWithNoInlineDescription() {
        let noDesc = """
        NXJERRJE LLOGARIE DEBI KREDI PERSHKRIMI
        29/05/26 31/05/26 -550.00 309,709.86
        29/05/26 29/05/26 260,000.00 569,709.86
        """
        let txns = RaiffeisenAlbaniaParser().parse(noDesc, currency: .all)
        XCTAssertEqual(txns.count, 2)
        XCTAssertEqual(txns[0].kind, .expense); XCTAssertEqual(txns[0].amount, 550)
        XCTAssertNil(txns[0].rawMerchant)                 // description was on another line
        XCTAssertEqual(txns[1].kind, .income);  XCTAssertEqual(txns[1].amount, 260000)
    }
}
