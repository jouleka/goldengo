import XCTest
@testable import GoldengoFeatures

final class AddIncomeViewTests: XCTestCase {
    // Switching to a zero-decimal currency (lek) drops the fractional part entirely, so a typed
    // "12.50" can never be logged as a fractional lek amount the keypad can no longer edit.
    func test_refit_toZeroDecimal_dropsFraction() {
        XCTAssertEqual(AddIncomeView.refitAmount("12.50", toFractionDigits: 0), "12")
        XCTAssertEqual(AddIncomeView.refitAmount("0.", toFractionDigits: 0), "0")
    }

    // A currency that allows fewer digits than typed truncates (never rounds — it's in-progress input).
    func test_refit_truncatesExcessDigits() {
        XCTAssertEqual(AddIncomeView.refitAmount("12.567", toFractionDigits: 2), "12.56")
    }

    // Within the allowed digits, the string is unchanged.
    func test_refit_keepsWhenWithinDigits() {
        XCTAssertEqual(AddIncomeView.refitAmount("12.5", toFractionDigits: 2), "12.5")
        XCTAssertEqual(AddIncomeView.refitAmount("12.50", toFractionDigits: 2), "12.50")
        XCTAssertEqual(AddIncomeView.refitAmount("12", toFractionDigits: 0), "12")
    }
}
