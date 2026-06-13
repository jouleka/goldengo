# Goldengo UI Rewrite — Phase 1: Design-System Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the "Quiet luxe" token + shared-component substrate in `GoldengoDesignSystem` so every later phase can reskin screens by inheriting it — with a real light/dark palette, one tabular amount renderer, one serif section header, one primary gold button, and the migrated theme tests.

**Architecture:** Pure design-system layer. We introduce a `Color(light:dark:)` resolver (none exists today), express the palette as testable hex constants under `GoldengoTheme.Hex`, migrate the existing `accent`/surface tokens off system colors onto the warm palette (keeping every public symbol name so no call site breaks), and add four small focused component files. TDD where logic exists (hex constants, amount sizing, button state mapping, spacing); build-gated for pure-presentation views.

**Tech Stack:** SwiftUI, SwiftPM module `GoldengoDesignSystem`, XCTest via `swift test`. Tests run on the macOS host, so the design system's `#if canImport(AppKit)` branch is what the test build compiles — all new color code must compile under AppKit.

**Spec:** `docs/superpowers/specs/2026-06-13-goldengo-ui-rewrite-design.md` (§2, §3). This plan implements §3 (Foundation) and decisions D1, D3, D5, D6, D7, D12.

**Branch:** `ui-rewrite-quiet-luxe` (already created).

---

## Scope & deferrals (surfaced, per spec §3.2)

Spec §3.2 lists several shared components "built once" in the foundation. This plan builds only the ones with an early consumer **and** a testable/buildable surface now: `Color(light:dark:)`, the palette tokens, `GoldengoAmountText`, `GoldengoSerifSectionHeader`, `GoldButton`, the `GoldengoCardStyle` hairline, and the keyboard helper. The following are **deferred to their first-consuming phase** to avoid building unused visual components (YAGNI):

- `AddFAB` → Phase 2 (nav shell)
- `SelectableChip` → Phase 4 (Add/Receipt/Edit; first used in Add)
- `DrainingPoolBar` → Phase 5 (Sources)
- `GoldGlyphBadge` → Phase 6 (Morning/Evening/ReEntry)

`GoldengoSectionLabel` (uppercase caption) is **not modified** (D3) — QuickAdd "Paid from" and Import depend on it.

---

## File structure

- **Modify** `Sources/GoldengoDesignSystem/GoldengoTheme.swift` — conditional UIKit/AppKit imports, `Color(light:dark:)` initializers, `GoldengoTheme.Hex` palette, repointed semantic tokens + warm surfaces, `accentGoldHex` value, `Spacing` aliases, `GoldengoCardStyle` hairline.
- **Create** `Sources/GoldengoDesignSystem/GoldengoAmountText.swift` — the single tabular amount renderer.
- **Create** `Sources/GoldengoDesignSystem/GoldButton.swift` — the primary gold CTA.
- **Create** `Sources/GoldengoDesignSystem/GoldengoSerifSectionHeader.swift` — serif section header.
- **Create** `Sources/GoldengoDesignSystem/GoldengoKeyboard.swift` — tap-outside dismissal helper.
- **Modify** `Tests/GoldengoDesignSystemTests/ThemeTests.swift` — migrate the gold-hex pin.
- **Create** `Tests/GoldengoDesignSystemTests/FoundationTests.swift` — palette hex, spacing aliases, amount sizing, button state mapping.

---

## Prerequisite

- [ ] **Confirm baseline green before changing anything**

Run: `cd /Users/jurgenleka/Public/WorkRepos/personal-work/goldengo && swift test --filter GoldengoDesignSystemTests`
Expected: PASS (3 tests: `test_goldAccentHex_isStable`, `test_spacingScale_isMonotonic`, `test_dangerColor_isDistinctFromGoldAccent`).
Confirm you are on branch `ui-rewrite-quiet-luxe` (`git branch --show-current`).

---

## Task 1: `Color(light:dark:)` resolver + palette hex constants

**Files:**
- Modify: `Sources/GoldengoDesignSystem/GoldengoTheme.swift`
- Test: `Tests/GoldengoDesignSystemTests/FoundationTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoDesignSystemTests/FoundationTests.swift`:

```swift
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
        // Smoke: the resolver compiles and builds a Color on the test host.
        _ = Color(light: "#000000", dark: "#FFFFFF")
        _ = Color(light: .black, dark: .white)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FoundationTests`
Expected: FAIL — compile error, `Hex` is not a member of `GoldengoTheme` and `Color(light:dark:)` does not exist.

- [ ] **Step 3: Add the conditional imports + resolver + palette**

In `Sources/GoldengoDesignSystem/GoldengoTheme.swift`, change the top imports (line 1) from:

```swift
import SwiftUI
```

to:

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
```

Then, inside `public enum GoldengoTheme {` (immediately after the opening brace at line 3, before `accentGoldHex`), add the palette:

```swift
    /// The locked "Quiet luxe" palette as hex (light, dark). This is the stable, testable contract;
    /// the `Color` tokens below are derived from it.
    public enum Hex {
        public static let canvasLight = "#F7F3EA"
        public static let canvasDark = "#17140F"
        public static let surfaceLight = "#FCFAF4"
        public static let surfaceDark = "#211D16"
        public static let fieldLight = "#EFE7D6"
        public static let fieldDark = "#2B261D"
        public static let inkPrimaryLight = "#2A2620"
        public static let inkPrimaryDark = "#F3ECDD"
        public static let inkMutedLight = "#8C8373"
        public static let inkMutedDark = "#A89E89"
        public static let hairlineLight = "#E7DECE"
        public static let hairlineDark = "#322C22"
        public static let accentLight = "#B68A2E"
        public static let accentDark = "#E0AE4A"
        public static let onAccent = "#2A2620"
    }
```

Then add the resolver to the `public extension Color` block. Immediately after the existing `init(hex:)` (after line 54), add:

```swift
    /// Resolves between two colors by the current interface style (light/dark).
    init(light: Color, dark: Color) {
#if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
#elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
#else
        self = light
#endif
    }

    /// Convenience: resolve between two hex strings.
    init(light: String, dark: String) {
        self.init(light: Color(hex: light), dark: Color(hex: dark))
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FoundationTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoDesignSystem/GoldengoTheme.swift Tests/GoldengoDesignSystemTests/FoundationTests.swift
git commit -m "feat(ui-foundation): Color(light:dark:) resolver + Quiet-luxe palette hex"
```

---

## Task 2: Migrate semantic tokens + warm surfaces (D1, D6, D7)

**Files:**
- Modify: `Sources/GoldengoDesignSystem/GoldengoTheme.swift`
- Test: `Tests/GoldengoDesignSystemTests/ThemeTests.swift`, `Tests/GoldengoDesignSystemTests/FoundationTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/GoldengoDesignSystemTests/ThemeTests.swift`, replace the body of `test_goldAccentHex_isStable` (line 7) so it pins the **new** light gold:

```swift
    func test_goldAccentHex_isStable() {
        // Light-mode gold is the back-compat single hex. Dark is asserted via Hex in FoundationTests.
        XCTAssertEqual(GoldengoTheme.accentGoldHex, "#B68A2E")
    }
```

In `FoundationTests.swift`, add a test that the back-compat hex maps to the light accent:

```swift
    func test_accentGoldHex_matchesLightAccent() {
        XCTAssertEqual(GoldengoTheme.accentGoldHex, GoldengoTheme.Hex.accentLight)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GoldengoDesignSystemTests`
Expected: FAIL — `test_goldAccentHex_isStable` fails (still `#E8B341`); `test_accentGoldHex_matchesLightAccent` fails (still `#E8B341` ≠ `#B68A2E`).

- [ ] **Step 3: Repoint the tokens**

In `GoldengoTheme.swift`, replace the accent block (lines 4–8) — currently:

```swift
    public static let accentGoldHex = "#E8B341"
    public static var accent: Color { Color(hex: accentGoldHex) }

    /// Faint gold wash used behind icons and selected states.
    public static var accentSoft: Color { accent.opacity(0.16) }
```

with:

```swift
    /// Light-mode gold hex. Kept for back-compat (was the single accent hex). Dark gold is `Hex.accentDark`.
    public static let accentGoldHex = Hex.accentLight

    /// The one brand accent. Sparingly used; semantic colors (danger/income) are separate.
    public static var accent: Color { Color(light: Hex.accentLight, dark: Hex.accentDark) }

    /// Faint gold wash behind icons and selected states. Per-scheme alpha (D6): 0.12 light / 0.16 dark.
    public static var accentSoft: Color {
        Color(light: Color(hex: Hex.accentLight).opacity(0.12),
              dark:  Color(hex: Hex.accentDark).opacity(0.16))
    }

    /// Foreground color for any label/glyph sitting on a gold fill (D1).
    public static var onAccent: Color { Color(hex: Hex.onAccent) }

    /// Primary text / amounts.
    public static var inkPrimary: Color { Color(light: Hex.inkPrimaryLight, dark: Hex.inkPrimaryDark) }

    /// Secondary text, captions.
    public static var inkMuted: Color { Color(light: Hex.inkMutedLight, dark: Hex.inkMutedDark) }

    /// 1px separators and card strokes.
    public static var hairline: Color { Color(light: Hex.hairlineLight, dark: Hex.hairlineDark) }
```

Then replace the three `Color` surface tokens (lines 56–87) so they use the warm palette. Replace the bodies of `goldengoBackground`, `goldengoSurface`, and `goldengoField` with:

```swift
    /// The app canvas (the warm backdrop cards sit on).
    static var goldengoBackground: Color {
        Color(light: GoldengoTheme.Hex.canvasLight, dark: GoldengoTheme.Hex.canvasDark)
    }

    /// An elevated card / row surface.
    static var goldengoSurface: Color {
        Color(light: GoldengoTheme.Hex.surfaceLight, dark: GoldengoTheme.Hex.surfaceDark)
    }

    /// A subtle fill for fields and keypad keys.
    static var goldengoField: Color {
        Color(light: GoldengoTheme.Hex.fieldLight, dark: GoldengoTheme.Hex.fieldDark)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GoldengoDesignSystemTests`
Expected: PASS. `test_dangerColor_isDistinctFromGoldAccent` must still pass (system red ≠ dynamic gold). If `XCTAssertNotEqual` on `Color` proves unreliable for the dynamic accent, change that assertion to compare against the resolved light gold hex instead: `XCTAssertNotEqual(GoldengoTheme.accentGoldHex, "#FF0000")` is NOT sufficient — instead keep the Color compare and confirm it passes; only if it fails, file it as a surfaced finding rather than weakening the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoDesignSystem/GoldengoTheme.swift Tests/GoldengoDesignSystemTests/
git commit -m "feat(ui-foundation): warm palette tokens (ink/hairline/onAccent) + dark surfaces; migrate gold to #B68A2E/#E0AE4A"
```

---

## Task 3: Spacing aliases (additive, order-preserving)

**Files:**
- Modify: `Sources/GoldengoDesignSystem/GoldengoTheme.swift`
- Test: `Tests/GoldengoDesignSystemTests/FoundationTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `FoundationTests.swift`:

```swift
    func test_spacingAliases_matchBaseScale() {
        XCTAssertEqual(GoldengoTheme.Spacing.xs4, GoldengoTheme.Spacing.xs)
        XCTAssertEqual(GoldengoTheme.Spacing.s8, GoldengoTheme.Spacing.s)
        XCTAssertEqual(GoldengoTheme.Spacing.m16, GoldengoTheme.Spacing.m)
        XCTAssertEqual(GoldengoTheme.Spacing.l24, GoldengoTheme.Spacing.l)
        XCTAssertEqual(GoldengoTheme.Spacing.xl32, GoldengoTheme.Spacing.xl)
        XCTAssertEqual(GoldengoTheme.Spacing.xs4, 4)
        XCTAssertEqual(GoldengoTheme.Spacing.xl32, 32)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FoundationTests`
Expected: FAIL — `xs4`/`s8`/`m16`/`l24`/`xl32` not members of `Spacing`.

- [ ] **Step 3: Add the aliases**

In `GoldengoTheme.swift`, inside `public enum Spacing` (after line 27, before the closing brace at line 28), add:

```swift
        // Named aliases (same values) used by the rewrite spec; additive — base names retained.
        public static let xs4: CGFloat = xs
        public static let s8: CGFloat = s
        public static let m16: CGFloat = m
        public static let l24: CGFloat = l
        public static let xl32: CGFloat = xl
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FoundationTests`
Expected: PASS. `test_spacingScale_isMonotonic` (in ThemeTests) still PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoDesignSystem/GoldengoTheme.swift Tests/GoldengoDesignSystemTests/FoundationTests.swift
git commit -m "feat(ui-foundation): additive Spacing aliases (xs4..xl32)"
```

---

## Task 4: `GoldengoAmountText` — the single tabular amount renderer (D5)

**Files:**
- Create: `Sources/GoldengoDesignSystem/GoldengoAmountText.swift`
- Test: `Tests/GoldengoDesignSystemTests/FoundationTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `FoundationTests.swift`:

```swift
    func test_amountText_pointSizes_areMonotonicByRole() {
        let hero = GoldengoAmountText.pointSize(for: .hero)
        let title = GoldengoAmountText.pointSize(for: .title)
        let row = GoldengoAmountText.pointSize(for: .row)
        let micro = GoldengoAmountText.pointSize(for: .micro)
        XCTAssertEqual(hero, 44)
        XCTAssertEqual(row, 17)
        XCTAssertGreaterThan(hero, title)
        XCTAssertGreaterThan(title, row)
        XCTAssertGreaterThan(row, micro)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FoundationTests`
Expected: FAIL — `GoldengoAmountText` is undefined.

- [ ] **Step 3: Create the component**

Create `Sources/GoldengoDesignSystem/GoldengoAmountText.swift`:

```swift
import SwiftUI

/// The single renderer for every monetary amount in the app: tabular figures, semibold, tight
/// tracking, and an in-place numeric transition. Takes a pre-formatted string (amounts arrive
/// already localized from `Money.formatted()`); `role` sets the size.
public struct GoldengoAmountText: View {
    public enum Role: CaseIterable { case hero, title, row, micro }

    private let text: String
    private let role: Role

    public init(_ text: String, role: Role = .row) {
        self.text = text
        self.role = role
    }

    public static func pointSize(for role: Role) -> CGFloat {
        switch role {
        case .hero:  return 44
        case .title: return 30
        case .row:   return 17
        case .micro: return 13
        }
    }

    public static func tracking(for role: Role) -> CGFloat {
        switch role {
        case .hero:  return -1.0
        case .title: return -0.5
        case .row:   return -0.2
        case .micro: return 0
        }
    }

    public var body: some View {
        Text(text)
            .font(.system(size: Self.pointSize(for: role), weight: .semibold))
            .monospacedDigit()
            .tracking(Self.tracking(for: role))
            .foregroundStyle(GoldengoTheme.inkPrimary)
            .contentTransition(.numericText())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FoundationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoDesignSystem/GoldengoAmountText.swift Tests/GoldengoDesignSystemTests/FoundationTests.swift
git commit -m "feat(ui-foundation): GoldengoAmountText — single tabular amount renderer"
```

---

## Task 5: `GoldButton` — the primary gold CTA (D1)

**Files:**
- Create: `Sources/GoldengoDesignSystem/GoldButton.swift`
- Test: `Tests/GoldengoDesignSystemTests/FoundationTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `FoundationTests.swift`:

```swift
    func test_goldButton_stateMapping() {
        XCTAssertEqual(GoldButton.fill(isEnabled: true), .accent)
        XCTAssertEqual(GoldButton.fill(isEnabled: false), .field)
        XCTAssertEqual(GoldButton.labelTint(isEnabled: true), .onAccent)
        XCTAssertEqual(GoldButton.labelTint(isEnabled: false), .muted)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FoundationTests`
Expected: FAIL — `GoldButton` is undefined.

- [ ] **Step 3: Create the component**

Create `Sources/GoldengoDesignSystem/GoldButton.swift`:

```swift
import SwiftUI

/// Full-width primary call-to-action. Gold fill + `onAccent` label when enabled; quiet `field`
/// fill + muted label when disabled. The single primary button across Add/Save/Done CTAs.
public struct GoldButton: View {
    public enum Fill: Equatable { case accent, field }
    public enum LabelTint: Equatable { case onAccent, muted }

    /// Pure state→fill mapping (testable).
    public static func fill(isEnabled: Bool) -> Fill { isEnabled ? .accent : .field }
    /// Pure state→label-tint mapping (testable).
    public static func labelTint(isEnabled: Bool) -> LabelTint { isEnabled ? .onAccent : .muted }

    private let title: String
    private let systemImage: String?
    private let isEnabled: Bool
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: GoldengoTheme.Spacing.s) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, GoldengoTheme.Spacing.m)
        }
        .buttonStyle(.plain)
        .background(fillColor)
        .foregroundStyle(labelColor)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
        .disabled(!isEnabled)
    }

    private var fillColor: Color {
        Self.fill(isEnabled: isEnabled) == .accent ? GoldengoTheme.accent : Color.goldengoField
    }
    private var labelColor: Color {
        Self.labelTint(isEnabled: isEnabled) == .onAccent ? GoldengoTheme.onAccent : GoldengoTheme.inkMuted
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FoundationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoDesignSystem/GoldButton.swift Tests/GoldengoDesignSystemTests/FoundationTests.swift
git commit -m "feat(ui-foundation): GoldButton — primary gold CTA with state mapping"
```

---

## Task 6: Serif section header, keyboard helper, card hairline (build-gated; D3)

These are pure-presentation (no branching logic to assert meaningfully — per Rule 9 we do not write tests that cannot fail). They are gated by the compile + the final full-suite run.

**Files:**
- Create: `Sources/GoldengoDesignSystem/GoldengoSerifSectionHeader.swift`
- Create: `Sources/GoldengoDesignSystem/GoldengoKeyboard.swift`
- Modify: `Sources/GoldengoDesignSystem/GoldengoTheme.swift` (card hairline)

- [ ] **Step 1: Create the serif section header**

Create `Sources/GoldengoDesignSystem/GoldengoSerifSectionHeader.swift`:

```swift
import SwiftUI

/// The serif "voice" section header for the rewrite. Distinct from `GoldengoSectionLabel`
/// (uppercase caption), which is kept for the screens that still use it (D3).
public struct GoldengoSerifSectionHeader: View {
    private let title: String
    private let hint: String?

    public init(_ title: String, hint: String? = nil) {
        self.title = title
        self.hint = hint
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(GoldengoTheme.inkPrimary)
            if let hint {
                Spacer(minLength: GoldengoTheme.Spacing.s)
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(GoldengoTheme.inkMuted)
            }
        }
    }
}
```

- [ ] **Step 2: Create the keyboard helper**

Create `Sources/GoldengoDesignSystem/GoldengoKeyboard.swift`:

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Keyboard dismissal that never relies on a "Done" toolbar (project rule): resign first
/// responder programmatically (use after an action) or via `goldengoDismissKeyboard()` (tap-outside).
public enum GoldengoKeyboard {
    public static func dismiss() {
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
}

public extension View {
    /// Tap-outside keyboard dismissal. Apply to a background layer, NOT over interactive controls,
    /// so it does not swallow their taps.
    func goldengoDismissKeyboard() -> some View {
        contentShape(Rectangle())
            .onTapGesture { GoldengoKeyboard.dismiss() }
    }
}
```

- [ ] **Step 3: Add the card hairline**

In `GoldengoTheme.swift`, in `GoldengoCardStyle.body` (lines 94–100), add a hairline overlay after the `clipShape`. Replace:

```swift
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.goldengoSurface)
            .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
```

with:

```swift
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.goldengoSurface)
            .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GoldengoTheme.Radius.card, style: .continuous)
                    .strokeBorder(GoldengoTheme.hairline, lineWidth: 1)
            )
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: Build complete, no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoDesignSystem/
git commit -m "feat(ui-foundation): GoldengoSerifSectionHeader, keyboard helper, card hairline"
```

---

## Task 7: Full-suite checkpoint + consumer audit

**Files:** none (verification only)

- [ ] **Step 1: Run the FULL test suite**

Run: `swift test`
Expected: PASS, all targets (per project memory: always run the full `swift test`, not just the design-system filter — the SwiftData Decimal/#Predicate segfault has bitten before).

- [ ] **Step 2: Audit consumers of the changed gold hex**

Run: `grep -rn "accentGoldHex\|#E8B341" Sources`
Expected: any remaining reference now resolves to the new `#B68A2E` light gold (intended — the widget/`WidgetTheme` parity is handled in Phase 7). If any consumer requires the OLD `#E8B341`, STOP and surface it rather than assuming the new value is correct everywhere.

- [ ] **Step 3: Confirm no call site broke from the token migration**

Run: `swift build 2>&1 | grep -i "error:" || echo "clean"`
Expected: `clean`. Public symbol names were preserved (`accent`, `accentSoft`, `goldengoBackground/Surface/Field`, `Spacing.xs..xl`), so consumers in `GoldengoFeatures` should compile unchanged.

- [ ] **Step 4: Final checkpoint commit (if any audit fixes were needed)**

If steps 1–3 surfaced fixes, make them and commit:

```bash
git add -A
git commit -m "fix(ui-foundation): address consumer audit from token migration"
```

If nothing needed fixing, this phase is complete — `git log --oneline` should show the Task 1–6 commits on `ui-rewrite-quiet-luxe`.

---

## Self-review (done while writing)

- **Spec coverage:** Foundation items in spec §3.1/§3.2 with an early consumer are all covered — `Color(light:dark:)` (T1), palette + ink/hairline/onAccent + accentSoft split + gold migration (T2), spacing aliases (T3), `GoldengoAmountText` (T4), `GoldButton` (T5), serif header + keyboard helper + card hairline (T6). ThemeTests migration (T2, D12-pragmatic). Deferred components are explicitly listed under "Scope & deferrals."
- **D12 deviation (surfaced):** the spec proposed resolved-cgColor assertions under fixed trait collections; this plan pins the **hex constants** instead, because resolved-color comparison is not reliable on the macOS `swift test` host. The hex contract is deterministic and cross-platform. This is an intentional, documented deviation.
- **Placeholder scan:** no TBD/TODO; every code step shows full code; every run step shows the command + expected result.
- **Type consistency:** `GoldengoTheme.Hex.*`, `Color(light:dark:)`, `GoldengoAmountText.Role`/`pointSize`/`tracking`, `GoldButton.Fill`/`LabelTint`/`fill`/`labelTint` are named identically across the tasks that define and test them.

## Definition of done

- `swift test` green (existing 3 theme tests, adjusted; new FoundationTests).
- `GoldengoDesignSystem` exposes the warm light/dark palette, `Color(light:dark:)`, `GoldengoAmountText`, `GoldButton`, `GoldengoSerifSectionHeader`, the keyboard helper, and the card hairline — with every previously-public symbol name intact.
- `GoldengoFeatures` still builds without modification.
