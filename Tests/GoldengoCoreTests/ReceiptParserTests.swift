import XCTest
import CoreGraphics
@testable import GoldengoCore

final class ReceiptParserTests: XCTestCase {
    /// A line at vertical position `y` (0 = bottom of receipt, 1 = top; origin bottom-left).
    private func line(_ text: String, y: Double) -> RecognizedLine {
        RecognizedLine(text: text, boundingBox: CGRect(x: 0.1, y: y, width: 0.8, height: 0.03))
    }

    private func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return cal.date(from: c)!
    }

    // MARK: Amount

    func test_amount_prefersTotalKeywordLine_overSubtotalAndTax() {
        let lines = [
            line("SPAR TIRANA", y: 0.95),
            line("Subtotal 1000", y: 0.40),
            line("TVSH 200", y: 0.30),
            line("TOTALI 1200 L", y: 0.20),
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).amount, 1200,
                       "Must pick the TOTAL line, not the subtotal or tax.")
    }

    func test_amount_lek_stripsThousandsSeparator_noDecimals() {
        XCTAssertEqual(ReceiptParser.parse([line("TOTALI 1.250 L", y: 0.2)], currency: .all).amount, 1250)
    }

    func test_amount_twoDecimalCurrency_dotDecimal() {
        XCTAssertEqual(ReceiptParser.parse([line("TOTAL $12.50", y: 0.2)], currency: CurrencyCode("USD")).amount,
                       Decimal(string: "12.50"))
    }

    func test_amount_twoDecimalCurrency_commaDecimal() {
        XCTAssertEqual(ReceiptParser.parse([line("TOTAL 12,50", y: 0.2)], currency: CurrencyCode("EUR")).amount,
                       Decimal(string: "12.50"))
    }

    func test_amount_fallsBackToLargestInLowerHalf_whenNoKeyword() {
        let lines = [
            line("ITEM A 300", y: 0.6),
            line("ITEM B 250", y: 0.5),
            line("900", y: 0.2),
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).amount, 900)
    }

    func test_amount_nilWhenNoNumbers() {
        XCTAssertNil(ReceiptParser.parse([line("THANK YOU", y: 0.2), line("SPAR", y: 0.9)], currency: .all).amount)
    }

    // MARK: Merchant

    func test_merchant_isTopMostNonNumericLine() {
        let lines = [
            line("SPAR TIRANA", y: 0.95),
            line("Rruga Myslym Shyri", y: 0.88),
            line("TOTALI 1200", y: 0.2),
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).merchant, "SPAR TIRANA")
    }

    func test_merchant_skipsNumericAndDateTopLines() {
        let lines = [
            line("2026-05-30", y: 0.97),
            line("0696 4471", y: 0.95),
            line("Cafe Bar Elida", y: 0.90),
            line("TOTALI 300", y: 0.2),
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).merchant, "Cafe Bar Elida")
    }

    func test_merchant_nilWhenNothingSuitable() {
        let lines = [line("1200", y: 0.9), line("2026-05-30", y: 0.8)]
        XCTAssertNil(ReceiptParser.parse(lines, currency: .all).merchant)
    }

    // MARK: Date

    func test_date_parsesISOFormat() {
        let lines = [line("Date: 2025-05-30", y: 0.8), line("TOTALI 1200", y: 0.2)]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).date, ymd(2025, 5, 30))
    }

    func test_date_parsesDayFirstDotFormat() {
        let lines = [line("30.05.2025 14:22", y: 0.8), line("TOTALI 1200", y: 0.2)]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).date, ymd(2025, 5, 30))
    }

    func test_date_nilWhenAbsent() {
        let lines = [line("SPAR", y: 0.9), line("TOTALI 1200", y: 0.2)]
        XCTAssertNil(ReceiptParser.parse(lines, currency: .all).date)
    }

    // Guards against the worst failure mode: a non-price number winning the no-keyword fallback.
    func test_amount_ignoresDateTokenInFallback() {
        let lines = [
            line("Cafe Elida", y: 0.95),
            line("30.05.2025", y: 0.30),   // a date, NOT the total
            line("1200", y: 0.15),         // the real (unlabeled) total
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).amount, 1200,
                       "A date in the lower half must never be mistaken for the total.")
    }

    func test_amount_ignoresLongIdTokenInFallback() {
        let lines = [
            line("NIPT 1234567890", y: 0.30),   // Albanian tax id on the footer
            line("950", y: 0.15),
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).amount, 950,
                       "A long id/code must never be mistaken for the total.")
    }

    // The fallback date guard must catch slash- and dash-separated dates too, not just dot-dates —
    // otherwise the year (e.g. 2025) leaks in as a digit run and wins the .max() fallback.
    func test_amount_ignoresSlashDateTokenInFallback() {
        let lines = [
            line("Cafe Elida", y: 0.95),
            line("30/05/2025", y: 0.30),   // a date, NOT the total
            line("1200", y: 0.15),         // the real (unlabeled) total
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).amount, 1200,
                       "A slash-separated date must never be mistaken for the total.")
    }

    func test_amount_ignoresDashDateTokenInFallback() {
        let lines = [
            line("Cafe Elida", y: 0.95),
            line("30-05-2025", y: 0.30),
            line("1200", y: 0.15),
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).amount, 1200,
                       "A dash-separated date must never be mistaken for the total.")
    }

    // A genuinely large lek total the user LABELED with a TOTAL keyword must survive the over-length
    // guard (the guard exists for unlabeled footer ids/phones, not for the labeled total).
    func test_amount_acceptsLargeLekTotalOnKeywordLine() {
        let lines = [
            line("SPAR TIRANA", y: 0.95),
            line("TOTALI 12.345.678 L", y: 0.20),
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).amount, 12345678,
                       "A large labeled total must not be rejected as an over-long id.")
    }

    // MARK: Line items

    func test_items_extractTrailingPrices_andIgnoreReceiptMath() {
        let lines = [
            line("SPAR TIRANA", y: 0.95),
            line("MILK 180", y: 0.72),
            line("SHAMPOO 420", y: 0.65),
            line("TVSH 100", y: 0.30),
            line("TOTALI 600 L", y: 0.20),
        ]
        let parsed = ReceiptParser.parse(lines, currency: .all)
        XCTAssertEqual(parsed.items.map(\.name), ["MILK", "SHAMPOO"])
        XCTAssertEqual(parsed.items.map(\.amount), [180, 420])
    }

    func test_items_allowPartialBasket_butRejectPriceOverTotal() {
        let lines = [
            line("SHOP", y: 0.95),
            line("BREAD 120", y: 0.70),
            line("LOYALTY ID 999999", y: 0.50),
            line("TOTAL 500", y: 0.20),
        ]
        XCTAssertEqual(ReceiptParser.parse(lines, currency: .all).items.map(\.name), ["BREAD"])
    }
}
