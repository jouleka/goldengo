import XCTest
import SwiftUI
@testable import GoldengoDesignSystem

final class ThemeTests: XCTestCase {
    func test_goldAccentHex_isStable() {
        XCTAssertEqual(GoldengoTheme.accentGoldHex, "#E8B341")
    }
    func test_spacingScale_isMonotonic() {
        XCTAssertLessThan(GoldengoTheme.Spacing.s, GoldengoTheme.Spacing.m)
        XCTAssertLessThan(GoldengoTheme.Spacing.m, GoldengoTheme.Spacing.l)
    }
    func test_dangerColor_isDistinctFromGoldAccent() {
        // The destructive (delete) tint must never collapse to the gold accent — a red delete
        // action that renders gold would be a real, user-facing defect.
        XCTAssertNotEqual(GoldengoTheme.danger, GoldengoTheme.accent)
    }
}
