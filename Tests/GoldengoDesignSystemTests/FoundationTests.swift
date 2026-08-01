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
        XCTAssertEqual(GoldengoTheme.Hex.inkMutedLight, "#71695C")
        XCTAssertEqual(GoldengoTheme.Hex.inkMutedDark, "#A89E89")
        XCTAssertEqual(GoldengoTheme.Hex.hairlineLight, "#E7DECE")
        XCTAssertEqual(GoldengoTheme.Hex.hairlineDark, "#322C22")
        XCTAssertEqual(GoldengoTheme.Hex.accentLight, "#8A671A")
        XCTAssertEqual(GoldengoTheme.Hex.accentDark, "#E0AE4A")
        XCTAssertEqual(GoldengoTheme.Hex.onAccent, "#2A2620")
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

    func test_goldButton_stateMapping() {
        XCTAssertEqual(GoldButton.fill(isEnabled: true), .accent)
        XCTAssertEqual(GoldButton.fill(isEnabled: false), .field)
        XCTAssertEqual(GoldButton.labelTint(isEnabled: true), .onAccent)
        XCTAssertEqual(GoldButton.labelTint(isEnabled: false), .muted)
    }

    func test_amountText_pointSizes_areMonotonicByRole() {
        let hero = GoldengoAmountText.pointSize(for: .hero)
        let title = GoldengoAmountText.pointSize(for: .title)
        let row = GoldengoAmountText.pointSize(for: .row)
        let micro = GoldengoAmountText.pointSize(for: .micro)
        XCTAssertEqual(hero, 52)
        XCTAssertEqual(row, 17)
        XCTAssertGreaterThan(hero, title)
        XCTAssertGreaterThan(title, row)
        XCTAssertGreaterThan(row, micro)
    }

#if canImport(AppKit)
    func test_accent_resolvesLightThenDark() {
        let light = resolvedSRGB(GoldengoTheme.accent, dark: false)
        XCTAssertEqual(light.r, 0.541, accuracy: 0.01)  // #8A671A
        XCTAssertEqual(light.g, 0.404, accuracy: 0.01)
        XCTAssertEqual(light.b, 0.102, accuracy: 0.01)
        let dark = resolvedSRGB(GoldengoTheme.accent, dark: true)
        XCTAssertEqual(dark.r, 0.878, accuracy: 0.01)   // #E0AE4A
        XCTAssertEqual(dark.g, 0.682, accuracy: 0.01)
        XCTAssertEqual(dark.b, 0.290, accuracy: 0.01)
        // The legs must not be swapped: dark gold is lighter (higher red) than light gold.
        XCTAssertGreaterThan(dark.r, light.r)
    }

    func test_accentSoft_alphaIsPerScheme() {
        XCTAssertEqual(resolvedSRGB(GoldengoTheme.accentSoft, dark: false).a, 0.12, accuracy: 0.01)
        XCTAssertEqual(resolvedSRGB(GoldengoTheme.accentSoft, dark: true).a, 0.16, accuracy: 0.01)
    }

    func test_onAccent_isColorConstantAcrossAppearance() {
        let light = resolvedSRGB(GoldengoTheme.onAccent, dark: false)
        let dark = resolvedSRGB(GoldengoTheme.onAccent, dark: true)
        XCTAssertEqual(light.r, dark.r, accuracy: 0.001)
        XCTAssertEqual(light.g, dark.g, accuracy: 0.001)
        XCTAssertEqual(light.b, dark.b, accuracy: 0.001)
    }

    func test_hex_sixDigit_parsesRGB() {
        let c = resolvedSRGB(Color(hex: "#FF8000"), dark: false)
        XCTAssertEqual(c.r, 1, accuracy: 0.01)
        XCTAssertEqual(c.g, 0.502, accuracy: 0.01)
        XCTAssertEqual(c.b, 0, accuracy: 0.01)
        XCTAssertEqual(c.a, 1, accuracy: 0.01)
    }

    // #RRGGBBAA — the trailing byte is alpha (0x80 ≈ 0.5), not discarded.
    func test_hex_eightDigit_parsesAlpha() {
        let c = resolvedSRGB(Color(hex: "#FF800080"), dark: false)
        XCTAssertEqual(c.r, 1, accuracy: 0.01)
        XCTAssertEqual(c.g, 0.502, accuracy: 0.01)
        XCTAssertEqual(c.b, 0, accuracy: 0.01)
        XCTAssertEqual(c.a, 0.502, accuracy: 0.01)
    }

    func test_hex_threeDigit_shorthandExpands() {
        let c = resolvedSRGB(Color(hex: "#F00"), dark: false)
        XCTAssertEqual(c.r, 1, accuracy: 0.01)
        XCTAssertEqual(c.g, 0, accuracy: 0.01)
        XCTAssertEqual(c.b, 0, accuracy: 0.01)
    }

    // Malformed input must be VISIBLY wrong (debug magenta), never a silent black that hides the bug.
    func test_hex_malformed_isNotSilentBlack() {
        let c = resolvedSRGB(Color(hex: "nope"), dark: false)
        XCTAssertFalse(c.r == 0 && c.g == 0 && c.b == 0, "Malformed hex must not silently resolve to black")
        XCTAssertEqual(c.r, 1, accuracy: 0.01)
        XCTAssertEqual(c.g, 0, accuracy: 0.01)
        XCTAssertEqual(c.b, 1, accuracy: 0.01)
    }
#endif
}

#if canImport(AppKit)
import AppKit

private func resolvedSRGB(_ color: Color, dark: Bool) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let ns = NSColor(color)
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    var out: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    appearance.performAsCurrentDrawingAppearance {
        let resolved = ns.usingColorSpace(.sRGB)!
        out = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent)
    }
    return out
}
#endif
