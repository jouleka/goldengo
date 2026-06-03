import XCTest
@testable import GoldengoCore

final class CurrencyInputTests: XCTestCase {
    // Switching to a no-minor-unit currency (lek) drops the decimal part entirely.
    func test_fit_dropsDecimals_forZeroDigitCurrency() {
        XCTAssertEqual(CurrencyInput.fit("12.50", toFractionDigits: 0), "12")
        XCTAssertEqual(CurrencyInput.fit("0.99", toFractionDigits: 0), "0")
    }

    // Switching to a lower-but-nonzero precision trims excess fractional digits.
    func test_fit_trimsToAllowedDigits() {
        XCTAssertEqual(CurrencyInput.fit("1.234", toFractionDigits: 2), "1.23")
    }

    // Within precision, the value is unchanged (no spurious reformatting).
    func test_fit_leavesValueUnchanged_whenWithinPrecision() {
        XCTAssertEqual(CurrencyInput.fit("12.50", toFractionDigits: 2), "12.50")
        XCTAssertEqual(CurrencyInput.fit("12.5", toFractionDigits: 2), "12.5")
    }

    // No decimal point → unchanged regardless of target precision.
    func test_fit_noDecimalPoint_unchanged() {
        XCTAssertEqual(CurrencyInput.fit("12", toFractionDigits: 0), "12")
        XCTAssertEqual(CurrencyInput.fit("12", toFractionDigits: 2), "12")
    }
}
