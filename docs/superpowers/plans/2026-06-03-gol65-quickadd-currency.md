# GOL-65 Quick Add Currency Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-tap per-transaction currency selector to Quick Add — the existing amount symbol becomes a Menu of common currencies plus a "More…" entry to the full searchable picker — switching currency live and keeping the typed amount valid.

**Architecture:** A pure, unit-tested amount sanitizer (`CurrencyInput`, GoldengoCore) trims a typed amount to the new currency's precision. `QuickAddModel.setCurrency` switches currency + sanitizes. `QuickAddView` turns the amount symbol into a `Menu` (common currencies + "More…" → the GOL-66 `CurrencyPickerView` in a sheet). Default-from-preferred and persist-on-expense are already wired (GOL-66/earlier).

**Tech Stack:** Swift 6, SwiftUI (`Menu`, `.sheet`, `NavigationStack`), XCTest. Reuses `CurrencyPickerView` + `CurrencyCatalog` from GOL-66. No new dependencies; no `project.rb` change (only existing GoldengoFeatures files + new GoldengoCore file, both globbed).

**Spec:** [docs/superpowers/specs/2026-06-03-gol65-quickadd-currency-design.md](../specs/2026-06-03-gol65-quickadd-currency-design.md)

**CI note:** GoldengoFeatures compiles on macOS for `swift test`; `Menu`, `.sheet`, `NavigationStack`, `Locale.localizedString` are all cross-platform. No iOS-only modifiers.

---

## File Structure

**Create (GoldengoCore):**
- `Sources/GoldengoCore/CurrencyInput.swift` — pure `fit(_:toFractionDigits:)` amount sanitizer.

**Modify (GoldengoFeatures):**
- `Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift` — add `setCurrency(_:)`.
- `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift` — currency `Menu` on the amount symbol + "More…" sheet.

**Modify (tests):**
- `Tests/GoldengoCoreTests/CurrencyInputTests.swift` (new).
- `Tests/GoldengoFeaturesTests/QuickAddModelTests.swift` (add `setCurrency` cases).

---

## Task 1: `CurrencyInput` — pure amount sanitizer

**Files:**
- Create: `Sources/GoldengoCore/CurrencyInput.swift`
- Test: `Tests/GoldengoCoreTests/CurrencyInputTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoCoreTests/CurrencyInputTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CurrencyInputTests`
Expected: FAIL — `CurrencyInput` does not exist.

- [ ] **Step 3: Create `CurrencyInput.swift`**

```swift
import Foundation

/// Pure helper for keypad amount entry. Keeps the app's "display == saved value" invariant when the
/// currency changes to one with fewer minor-unit digits.
public enum CurrencyInput {
    /// Trim a typed amount string so its fractional part fits `digits` minor-unit digits.
    public static func fit(_ amountString: String, toFractionDigits digits: Int) -> String {
        guard let dot = amountString.firstIndex(of: ".") else { return amountString }
        if digits == 0 { return String(amountString[..<dot]) }              // drop "." + all decimals
        let fracStart = amountString.index(after: dot)
        let fracCount = amountString.distance(from: fracStart, to: amountString.endIndex)
        guard fracCount > digits else { return amountString }
        return String(amountString[..<amountString.index(fracStart, offsetBy: digits)])
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CurrencyInputTests`
Expected: PASS (all 4)

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/CurrencyInput.swift Tests/GoldengoCoreTests/CurrencyInputTests.swift
git commit -m "feat(core): add CurrencyInput amount sanitizer"
```

---

## Task 2: `QuickAddModel.setCurrency(_:)`

**Files:**
- Modify: `Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift`
- Test: `Tests/GoldengoFeaturesTests/QuickAddModelTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/GoldengoFeaturesTests/QuickAddModelTests.swift`, add these methods inside the class (it
already has `makeModel(_ currency:)` and is `@MainActor`):

```swift
    func test_setCurrency_truncatesTypedAmount_whenSwitchingToZeroDecimalCurrency() throws {
        let m = try makeModel(.eur)                 // euro: 2 decimals
        m.tap("1"); m.tap("2"); m.tap("."); m.tap("5"); m.tap("0")
        XCTAssertEqual(m.amountString, "12.50")
        m.setCurrency(.all)                         // lek: no minor unit
        XCTAssertEqual(m.currency, .all)
        XCTAssertEqual(m.amountString, "12")        // decimals dropped → display == saved value
        XCTAssertFalse(m.allowsDecimal)             // "." key now hidden
    }

    func test_setCurrency_keepsAmount_whenSwitchingToHigherPrecision() throws {
        let m = try makeModel(.all)                 // lek
        m.tap("1"); m.tap("5"); m.tap("0")
        m.setCurrency(.eur)                          // euro
        XCTAssertEqual(m.currency, .eur)
        XCTAssertEqual(m.amountString, "150")        // integer amount unaffected
        XCTAssertTrue(m.allowsDecimal)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter QuickAddModelTests`
Expected: FAIL — `setCurrency` does not exist.

- [ ] **Step 3: Add `setCurrency` to `QuickAddModel`**

In `Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift`, add this method (e.g. just after the
`init`, before `amountDecimal`):

```swift
    /// Switch the currency for the in-progress expense, trimming the typed amount so it stays valid
    /// for the new currency's precision (e.g. €12.50 → L12). The symbol, "." key, and amount update
    /// via Observation.
    public func setCurrency(_ code: CurrencyCode) {
        currency = code
        amountString = CurrencyInput.fit(amountString, toFractionDigits: code.fractionDigits)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter QuickAddModelTests`
Expected: PASS (existing 7 + new 2).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift Tests/GoldengoFeaturesTests/QuickAddModelTests.swift
git commit -m "feat(features): QuickAddModel.setCurrency switches currency + sanitizes amount"
```

---

## Task 3: Quick Add currency `Menu` + "More…" sheet

**Files:**
- Modify: `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift`

UI — verified by build + runtime (Task 4). The menu follows the Goldengo design language established
in GOL-66 (gold accent, refined-minimal) — the symbol stays the hero with a subtle `chevron.down`
affordance.

- [ ] **Step 1: Add imports**

In `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift`, change the top imports from:

```swift
import SwiftUI
import GoldengoDesignSystem
```

to:

```swift
import SwiftUI
import GoldengoDesignSystem
import GoldengoCore
import GoldengoData
```

- [ ] **Step 2: Add the sheet-presentation state**

Replace:

```swift
    @State private var showAdded = false
```

with:

```swift
    @State private var showAdded = false
    @State private var showCurrencyPicker = false
```

- [ ] **Step 3: Present the "More…" picker as a sheet**

Replace:

```swift
        .background(Color.goldengoBackground.ignoresSafeArea())
        .alert("Couldn't save", isPresented: Binding(
```

with:

```swift
        .background(Color.goldengoBackground.ignoresSafeArea())
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencyPickerView(
                    available: availableCurrencies,
                    selectedCode: Binding(
                        get: { model.currency.rawValue },
                        set: { model.setCurrency(CurrencyCode($0)) }
                    )
                )
            }
        }
        .alert("Couldn't save", isPresented: Binding(
```

- [ ] **Step 4: Make the amount symbol a Menu**

In `amountDisplay`, replace:

```swift
                Text(model.currency.symbol)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
```

with:

```swift
                currencyMenu
```

- [ ] **Step 5: Add the menu + helpers**

Insert this block immediately before the `// MARK: - Categories` line:

```swift
    // MARK: - Currency

    private var currencyMenu: some View {
        Menu {
            ForEach(menuCurrencies, id: \.rawValue) { c in
                Button {
                    model.setCurrency(c)
                } label: {
                    if c.rawValue == model.currency.rawValue {
                        Label(menuLabel(c), systemImage: "checkmark")
                    } else {
                        Text(menuLabel(c))
                    }
                }
            }
            Divider()
            Button {
                showCurrencyPicker = true
            } label: {
                Label("More currencies…", systemImage: "ellipsis.circle")
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(model.currency.symbol)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
    }

    private func menuLabel(_ c: CurrencyCode) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol)  \(name)"
    }

    private var availableCurrencies: [CurrencyCode] {
        CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
    }

    private var menuCurrencies: [CurrencyCode] {
        let have = Set(availableCurrencies.map(\.rawValue))
        var list = CurrencyCode.popular.filter { have.contains($0.rawValue) }
        if !list.contains(where: { $0.rawValue == model.currency.rawValue }) {
            list.insert(model.currency, at: 0)   // keep the current currency reachable
        }
        return list
    }

```

- [ ] **Step 6: Build the package (macOS/CI) + the app**

Run: `swift build`
Expected: clean (no iOS-only API).

Run:
```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath AppProject/.build build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Run the full unit suite**

Run: `swift test`
Expected: PASS — all prior tests plus Tasks 1–2's new ones.

- [ ] **Step 8: Commit**

```bash
git add Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift
git commit -m "feat(features): per-transaction currency Menu in Quick Add"
```

---

## Task 4: Runtime verification + review

**Files:** none (verification only).

- [ ] **Step 1: Sim screenshot of the affordance**

```bash
APP="$(find AppProject/.build/Build/Products -name 'Goldengo.app' -path '*Debug-iphonesimulator*' | head -1)"
xcrun simctl boot "iPhone 17" 2>/dev/null || true
xcrun simctl install booted "$APP"
SIMCTL_CHILD_GOLDENGO_SEED_SAMPLE=1 xcrun simctl launch booted com.goldengo.app
xcrun simctl openurl booted goldengo://quickadd
xcrun simctl io booted screenshot /tmp/gol65-quickadd.png
```
Confirm the amount shows the currency symbol with a small `chevron.down` next to it. Capture os_log:
```bash
xcrun simctl spawn booted log show --last 30s --predicate 'process == "Goldengo"' --style compact | grep -iE 'AttributeGraph|modifying state|cycle detected|hang|fatal'
```
Expected: empty (no cycles/hangs).

- [ ] **Step 2: Device tap-test (gestures the sim can't drive)**

Build + install on the paired iPhone (per CLAUDE.md device build) so the user can confirm: tap the
symbol → menu lists common currencies with a checkmark on the current → switch lek↔euro (symbol + "."
key update; a typed €12.50 becomes L12) → "More currencies…" opens the searchable picker → pick a
searched currency → it applies and saving logs the expense in that currency.

- [ ] **Step 3: Second-Opus review**

Dispatch a general-purpose Opus 4.8 reviewer over `git diff main...HEAD` for GOL-65. Focus: the
`CurrencyInput` edge cases, `setCurrency` correctness, the `Binding` bridge in the sheet, no iOS-only
API on the macOS build, the menu's `menuCurrencies` dedup/current-inclusion, GoldengoTheme/minimalism,
and that nothing touches totals/conversion (GOL-68). Fix findings; re-run `swift test`.

- [ ] **Step 4: Final green gate**

Run: `swift test`
Expected: PASS. Branch ready to ff-merge to `main`.

---

## Self-Review

**1. Spec coverage:**
- Tap symbol → Menu of common currencies + "More…" → reused picker sheet → Tasks 3. ✓
- Pure amount sanitizer (euro→lek truncation, etc.) → Task 1. ✓
- `QuickAddModel.setCurrency` (switch + sanitize, live symbol/"." key) → Task 2. ✓
- Default = preferred + persist on expense → already wired (GOL-66/`logManual`); no task needed, noted. ✓
- Tests: pure sanitizer + direct `setCurrency` model tests + UI build/runtime/device → Tasks 1, 2, 3, 4. ✓
- Scope: no conversion/totals → confirmed (only currency selection); reuses GOL-66 picker. ✓
- Second-Opus review + os_log/screenshot/device → Task 4. ✓

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N". All code blocks complete; the sanitizer and menu are shown in full.

**3. Type consistency:** `CurrencyInput.fit(_:toFractionDigits:)`, `QuickAddModel.setCurrency(_:)`, `CurrencyCatalog.selectable(from:)`, `CurrencyPickerView(available:selectedCode:)`, `CurrencyCode.popular`/`.symbol`/`.rawValue`/`.fractionDigits`, `ExchangeRateCache().load()`, `SeedRates.table` — all match the signatures shipped in GOL-66/67 and used consistently here.
