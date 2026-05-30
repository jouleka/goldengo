import XCTest
@testable import GoldengoCore

final class MoneyTests: XCTestCase {
    func test_lek_formatsWithSymbol_noDecimals_groupingSeparator() {
        let m = Money(amount: 1500, currency: .all)
        XCTAssertEqual(m.formatted(), "L 1,500")
    }

    func test_eur_formatsWithSymbol_twoDecimals() {
        let m = Money(amount: Decimal(string: "12.5")!, currency: .eur)
        XCTAssertEqual(m.formatted(), "€ 12.50")
    }

    func test_unknownCurrency_usesRawCodeAsSymbol() {
        let m = Money(amount: 3, currency: CurrencyCode("BTC"))
        XCTAssertEqual(m.currency.symbol, "BTC")
    }

    func test_currencyCode_isUppercasedAndEquatable() {
        XCTAssertEqual(CurrencyCode("eur"), .eur)
    }

    func test_negativeLek_placesSignBeforeSymbol() {
        let m = Money(amount: -1500, currency: .all)
        XCTAssertEqual(m.formatted(), "-L 1,500")
    }

    func test_negativeEur_placesSignBeforeSymbol_twoDecimals() {
        let m = Money(amount: Decimal(string: "-12.5")!, currency: .eur)
        XCTAssertEqual(m.formatted(), "-€ 12.50")
    }
}
