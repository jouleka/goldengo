import XCTest
import SwiftUI
@testable import GoldengoDesignSystem

final class FoundationTests: XCTestCase {
    func test_palette_hexValues_areLocked() {
        XCTAssertEqual(GoldengoTheme.Hex.canvasLight, "#F7F3EA")
        XCTAssertEqual(GoldengoTheme.Hex.canvasDark, "#17140F")
        XCTAssertEqual(GoldengoTheme.Hex.surfaceLight, "#FCFAF4")
        XCTAssertEqual(GoldengoTheme.Hex.surfaceDark, "#211D16")
        XCTAssertEqual(GoldengoTheme.Hex.fieldLight, "#EFE7D6")
        XCTAssertEqual(GoldengoTheme.Hex.fieldDark, "#2B261D")
        XCTAssertEqual(GoldengoTheme.Hex.inkPrimaryLight, "#2A2620")
        XCTAssertEqual(GoldengoTheme.Hex.inkPrimaryDark, "#F3ECDD")
        XCTAssertEqual(GoldengoTheme.Hex.inkMutedLight, "#8C8373")
        XCTAssertEqual(GoldengoTheme.Hex.inkMutedDark, "#A89E89")
        XCTAssertEqual(GoldengoTheme.Hex.hairlineLight, "#E7DECE")
        XCTAssertEqual(GoldengoTheme.Hex.hairlineDark, "#322C22")
        XCTAssertEqual(GoldengoTheme.Hex.accentLight, "#B68A2E")
        XCTAssertEqual(GoldengoTheme.Hex.accentDark, "#E0AE4A")
        XCTAssertEqual(GoldengoTheme.Hex.onAccent, "#2A2620")
    }

    func test_dynamicColor_isConstructible() {
        _ = Color(light: "#000000", dark: "#FFFFFF")
        _ = Color(light: .black, dark: .white)
    }

    func test_accentGoldHex_matchesLightAccent() {
        XCTAssertEqual(GoldengoTheme.accentGoldHex, GoldengoTheme.Hex.accentLight)
    }

    func test_spacingAliases_matchBaseScale() {
        XCTAssertEqual(GoldengoTheme.Spacing.xs4, GoldengoTheme.Spacing.xs)
        XCTAssertEqual(GoldengoTheme.Spacing.s8, GoldengoTheme.Spacing.s)
        XCTAssertEqual(GoldengoTheme.Spacing.m16, GoldengoTheme.Spacing.m)
        XCTAssertEqual(GoldengoTheme.Spacing.l24, GoldengoTheme.Spacing.l)
        XCTAssertEqual(GoldengoTheme.Spacing.xl32, GoldengoTheme.Spacing.xl)
        XCTAssertEqual(GoldengoTheme.Spacing.xs4, 4)
        XCTAssertEqual(GoldengoTheme.Spacing.xl32, 32)
    }
}
