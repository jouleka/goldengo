import XCTest
@testable import GoldengoDesignSystem

final class ThemeTests: XCTestCase {
    func test_goldAccentHex_isStable() {
        XCTAssertEqual(GoldengoTheme.accentGoldHex, "#E8B341")
    }
    func test_spacingScale_isMonotonic() {
        XCTAssertLessThan(GoldengoTheme.Spacing.s, GoldengoTheme.Spacing.m)
        XCTAssertLessThan(GoldengoTheme.Spacing.m, GoldengoTheme.Spacing.l)
    }
}
