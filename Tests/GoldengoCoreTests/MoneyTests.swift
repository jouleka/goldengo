import XCTest
@testable import GoldengoCore

final class MoneyTests: XCTestCase {
    func test_lek_formatsWithSymbol_noDecimals_groupingSeparator() {
        let m = Money(amount: 1500, currency: .all)
        XCTAssertEqual(m.formatted(), "ALL 1,500")   // lek shows its ISO code, not "L" (product choice)
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
        XCTAssertEqual(m.formatted(), "-ALL 1,500")
    }

    func test_negativeEur_placesSignBeforeSymbol_twoDecimals() {
        let m = Money(amount: Decimal(string: "-12.5")!, currency: .eur)
        XCTAssertEqual(m.formatted(), "-€ 12.50")
    }

    // amountText() is the signed number WITHOUT the symbol — for layouts that render the currency
    // separately (e.g. the dashboard's tappable currency control beside the amount).
    func test_amountText_omitsCurrencySymbol() {
        XCTAssertEqual(Money(amount: Decimal(string: "1383.98")!, currency: .eur).amountText(), "1,383.98")
        XCTAssertEqual(Money(amount: 1500, currency: .all).amountText(), "1,500")
        XCTAssertEqual(Money(amount: Decimal(string: "-12.5")!, currency: .eur).amountText(), "-12.50")
    }
}
