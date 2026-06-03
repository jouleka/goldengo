# GOL-66 Preferred Currency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted preferred currency in Settings (searchable picker, default lek) that drives the Quick Add default currency and the dashboard's display currency.

**Architecture:** Persist the ISO code in App-Group `UserDefaults` via `SharedSummary` (the existing settings pattern). Pure, testable helpers (`CurrencyCatalog`) provide the selectable universe (from the GOL-67 rate table, minus non-currencies) and the search filter. A `CurrencyPickerView` (searchable, Suggested + All) writes the code; `RootView` reads it and feeds it to `QuickAddModel` + `RecentExpensesModel`, re-applying on Settings dismissal.

**Tech Stack:** Swift 6, SwiftUI (`Form`/`List`/`.searchable`/`NavigationLink`), App-Group `UserDefaults`, `Locale.localizedString(forCurrencyCode:)` for names, XCTest. No new dependencies; no `project.rb` change (one new file is in the GoldengoFeatures package, globbed automatically; the app target is untouched).

**Spec:** [docs/superpowers/specs/2026-06-03-gol66-preferred-currency-design.md](../specs/2026-06-03-gol66-preferred-currency-design.md)

**CI note:** GoldengoFeatures compiles on macOS for `swift test`. Avoid iOS-only SwiftUI modifiers (e.g. `.navigationBarTitleDisplayMode`, `.listStyle(.insetGrouped)`); use cross-platform ones (`.navigationTitle`, plain `List`/`Form`), matching the existing `SettingsView`.

---

## File Structure

**Modify (GoldengoData):**
- `Sources/GoldengoData/SharedSummary.swift` — add `import GoldengoCore` + `preferredCurrencyKey` + `readPreferredCurrency()` / `setPreferredCurrency(_:)`.

**Create (GoldengoCore):**
- `Sources/GoldengoCore/CurrencyCatalog.swift` — `nonCurrencyCodes`, `selectable(from:)`, `filter(_:query:name:)`.

**Create (GoldengoFeatures):**
- `Sources/GoldengoFeatures/Settings/CurrencyPickerView.swift` — searchable picker.

**Modify (GoldengoFeatures):**
- `Sources/GoldengoFeatures/Settings/SettingsView.swift` — add `import GoldengoCore` + a "Currency" section.
- `Sources/GoldengoFeatures/RootView.swift` — own `quickAddModel`, seed both models from the preferred currency, re-apply on Settings dismiss.

**Create (tests):**
- Add to `Tests/GoldengoDataTests/SharedSummaryTests.swift` (preferred-currency cases).
- `Tests/GoldengoCoreTests/CurrencyCatalogTests.swift`.

---

## Task 1: Persist preferred currency in `SharedSummary`

**Files:**
- Modify: `Sources/GoldengoData/SharedSummary.swift`
- Test: `Tests/GoldengoDataTests/SharedSummaryTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/GoldengoDataTests/SharedSummaryTests.swift`, add `import GoldengoCore` under the existing `import` lines, and add these methods inside the class:

```swift
    func test_preferredCurrency_defaultsToLek_whenUnset() {
        let s = SharedSummary(suiteName: freshSuite())
        XCTAssertEqual(s.readPreferredCurrency(), .all)
    }

    func test_preferredCurrency_roundTrips() {
        let s = SharedSummary(suiteName: freshSuite())
        s.setPreferredCurrency(.eur)
        XCTAssertEqual(s.readPreferredCurrency(), .eur)
    }

    func test_preferredCurrency_persistsAcrossInstances_onSameSuite() {
        let suite = freshSuite()
        SharedSummary(suiteName: suite).setPreferredCurrency(CurrencyCode("USD"))
        XCTAssertEqual(SharedSummary(suiteName: suite).readPreferredCurrency(), CurrencyCode("USD"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SharedSummaryTests`
Expected: FAIL — `readPreferredCurrency` / `setPreferredCurrency` don't exist.

- [ ] **Step 3: Implement the accessors**

In `Sources/GoldengoData/SharedSummary.swift`, add `import GoldengoCore` at the top (after `import Foundation`). Add the key alongside the other `public static let` keys:

```swift
    public static let preferredCurrencyKey = "preferredCurrency"
```

Add these methods inside `SharedSummary` (e.g. after `setRevealOnLockScreen`):

```swift
    /// The user's preferred/display currency (ISO code). Defaults to lek when unset.
    public func readPreferredCurrency() -> CurrencyCode {
        let raw = defaults.string(forKey: Self.preferredCurrencyKey) ?? ""
        return raw.isEmpty ? .all : CurrencyCode(raw)
    }

    public func setPreferredCurrency(_ code: CurrencyCode) {
        defaults.set(code.rawValue, forKey: Self.preferredCurrencyKey)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SharedSummaryTests`
Expected: PASS (existing 4 + new 3).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/SharedSummary.swift Tests/GoldengoDataTests/SharedSummaryTests.swift
git commit -m "feat(data): persist preferred currency in SharedSummary"
```

---

## Task 2: `CurrencyCatalog` — selectable universe + search filter

**Files:**
- Create: `Sources/GoldengoCore/CurrencyCatalog.swift`
- Test: `Tests/GoldengoCoreTests/CurrencyCatalogTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoCoreTests/CurrencyCatalogTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class CurrencyCatalogTests: XCTestCase {
    private func table(_ codes: [String]) -> RateTable {
        var rates: [String: Decimal] = [:]
        for c in codes { rates[c] = 1 }
        return RateTable(base: CurrencyCode("USD"), rates: rates, asOf: Date(timeIntervalSince1970: 0))
    }

    // selectable() exposes spendable currencies and drops non-currency codes (metals, SDR).
    func test_selectable_excludesNonCurrencies() {
        let codes = CurrencyCatalog.selectable(from: table(["USD", "EUR", "ALL", "XAU", "XDR"]))
            .map(\.rawValue)
        XCTAssertTrue(codes.contains("USD"))
        XCTAssertTrue(codes.contains("ALL"))
        XCTAssertFalse(codes.contains("XAU"))
        XCTAssertFalse(codes.contains("XDR"))
    }

    // Empty query returns the input unchanged (no filtering).
    func test_filter_emptyQuery_returnsAll() {
        let input = [CurrencyCode("USD"), CurrencyCode("EUR")]
        XCTAssertEqual(CurrencyCatalog.filter(input, query: "  ", name: { _ in "" }), input)
    }

    // Matches by ISO code, case-insensitively.
    func test_filter_matchesByCode_caseInsensitive() {
        let input = [CurrencyCode("USD"), CurrencyCode("EUR"), CurrencyCode("ALL")]
        let out = CurrencyCatalog.filter(input, query: "eur", name: { _ in "" }).map(\.rawValue)
        XCTAssertEqual(out, ["EUR"])
    }

    // Matches by display name (injected), even when the code doesn't contain the query.
    func test_filter_matchesByName() {
        let input = [CurrencyCode("ALL"), CurrencyCode("EUR")]
        let names = ["ALL": "Albanian Lek", "EUR": "Euro"]
        let out = CurrencyCatalog.filter(input, query: "lek", name: { names[$0.rawValue] ?? "" }).map(\.rawValue)
        XCTAssertEqual(out, ["ALL"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CurrencyCatalogTests`
Expected: FAIL — `CurrencyCatalog` does not exist.

- [ ] **Step 3: Create `CurrencyCatalog.swift`**

```swift
import Foundation

/// Pure helpers for currency selection UIs. No `Locale`/UI dependency — the display-name lookup is
/// injected so the search filter stays deterministically unit-testable.
public enum CurrencyCatalog {
    /// Codes carried by FX feeds that aren't spendable everyday currencies (precious metals, SDR).
    public static let nonCurrencyCodes: Set<String> = ["XAU", "XAG", "XPD", "XPT", "XDR"]

    /// The selectable universe from a rate table: every rate code minus the non-currencies.
    public static func selectable(from table: RateTable) -> [CurrencyCode] {
        table.rates.keys
            .filter { !nonCurrencyCodes.contains($0) }
            .map(CurrencyCode.init)
    }

    /// Case-insensitive filter by ISO code OR display name. Empty query → input unchanged.
    public static func filter(_ codes: [CurrencyCode], query: String,
                              name: (CurrencyCode) -> String) -> [CurrencyCode] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return codes }
        return codes.filter {
            $0.rawValue.lowercased().contains(q) || name($0).lowercased().contains(q)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CurrencyCatalogTests`
Expected: PASS (all 4)

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/CurrencyCatalog.swift Tests/GoldengoCoreTests/CurrencyCatalogTests.swift
git commit -m "feat(core): add CurrencyCatalog (selectable universe + search filter)"
```

---

## Task 3: `CurrencyPickerView` (searchable picker)

**Files:**
- Create: `Sources/GoldengoFeatures/Settings/CurrencyPickerView.swift`

UI — verified by build + runtime (Task 6), not unit tests. The code below is a complete, working
baseline; **invoke the `/frontend-design` skill** to elevate spacing/typography/selected-state within
`GoldengoTheme` before finalizing (keep it cross-platform per the CI note).

- [ ] **Step 1: Create the picker**

```swift
import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

/// Searchable currency picker: a "Suggested" group (popular ∩ available) then all currencies,
/// or a flat filtered list while searching. Writes the chosen ISO code to `selectedCode`.
struct CurrencyPickerView: View {
    let available: [CurrencyCode]
    @Binding var selectedCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private func name(_ c: CurrencyCode) -> String {
        Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
    }
    private func byName(_ a: CurrencyCode, _ b: CurrencyCode) -> Bool {
        name(a).localizedCaseInsensitiveCompare(name(b)) == .orderedAscending
    }

    private var suggested: [CurrencyCode] {
        let have = Set(available.map(\.rawValue))
        return CurrencyCode.popular.filter { have.contains($0.rawValue) }
    }
    private var others: [CurrencyCode] {
        let pop = Set(CurrencyCode.popular.map(\.rawValue))
        return available.filter { !pop.contains($0.rawValue) }.sorted(by: byName)
    }
    private var results: [CurrencyCode] {
        CurrencyCatalog.filter(available, query: query, name: name).sorted(by: byName)
    }

    var body: some View {
        List {
            if query.isEmpty {
                Section("Suggested") { ForEach(suggested, id: \.rawValue, content: row) }
                Section("All currencies") { ForEach(others, id: \.rawValue, content: row) }
            } else {
                ForEach(results, id: \.rawValue, content: row)
            }
        }
        .searchable(text: $query, prompt: "Search currency")
        .navigationTitle("Currency")
    }

    private func row(_ c: CurrencyCode) -> some View {
        Button {
            selectedCode = c.rawValue
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(c.symbol)
                    .frame(width: 30, alignment: .leading)
                    .foregroundStyle(GoldengoTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name(c)).foregroundStyle(.primary)
                    Text(c.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if c.rawValue == selectedCode {
                    Image(systemName: "checkmark").foregroundStyle(GoldengoTheme.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build the package to verify it compiles (macOS, CI-equivalent)**

Run: `swift build`
Expected: builds with no errors/warnings. (If a modifier is iOS-only, the macOS build fails here — swap for a cross-platform one.)

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoFeatures/Settings/CurrencyPickerView.swift
git commit -m "feat(features): add searchable CurrencyPickerView"
```

---

## Task 4: Add the "Currency" section to `SettingsView`

**Files:**
- Modify: `Sources/GoldengoFeatures/Settings/SettingsView.swift`

- [ ] **Step 1: Add the import + AppStorage + computed helpers**

In `Sources/GoldengoFeatures/Settings/SettingsView.swift`, add `import GoldengoCore` after `import GoldengoData`. Add this `@AppStorage` next to the others (after `leadDays`):

```swift
    @AppStorage(SharedSummary.preferredCurrencyKey, store: UserDefaults(suiteName: SharedSummary.appGroupID))
    private var preferredCode: String = "ALL"
```

Add these computed properties inside the struct (e.g. just before `body`):

```swift
    private var availableCurrencies: [CurrencyCode] {
        CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)
    }
    private var preferredLabel: String {
        let c = CurrencyCode(preferredCode)
        let n = Locale.current.localizedString(forCurrencyCode: c.rawValue) ?? c.rawValue
        return "\(c.symbol) · \(n)"
    }
```

- [ ] **Step 2: Add the Currency section to the Form**

Insert this `Section` into the `Form` (e.g. as the first section, before "Privacy"):

```swift
                Section("Currency") {
                    NavigationLink {
                        CurrencyPickerView(available: availableCurrencies, selectedCode: $preferredCode)
                    } label: {
                        LabeledContent("Default currency", value: preferredLabel)
                    }
                    Text("Used as the default for new expenses and your dashboard total.")
                        .font(.caption).foregroundStyle(.secondary)
                }
```

- [ ] **Step 3: Build the app for the simulator**

Run:
```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath AppProject/.build build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoFeatures/Settings/SettingsView.swift
git commit -m "feat(features): add Currency section to Settings"
```

---

## Task 5: Wire the preferred currency into Quick Add + dashboard (`RootView`)

**Files:**
- Modify: `Sources/GoldengoFeatures/RootView.swift`

- [ ] **Step 1: Own `quickAddModel` and seed both models from the preferred currency**

In `Sources/GoldengoFeatures/RootView.swift`, add `import GoldengoCore` after `import GoldengoData`.

Add the state declaration next to `recentModel`/`subsModel`:

```swift
    @State private var quickAddModel: QuickAddModel
```

Replace the initializer body (currently lines 15–19) with:

```swift
    public init(store: IngestionStore) {
        self.store = store
        let preferred = SharedSummary().readPreferredCurrency()
        _recentModel = State(initialValue: RecentExpensesModel(store: store, currency: preferred))
        _subsModel = State(initialValue: SubscriptionsModel(store: store))
        _quickAddModel = State(initialValue: QuickAddModel(store: store, currency: preferred))
    }
```

- [ ] **Step 2: Use the owned model in the tab**

Replace the Add tab's view construction (currently line 41):

```swift
            QuickAddView(model: QuickAddModel(store: store))
```

with:

```swift
            QuickAddView(model: quickAddModel)
```

- [ ] **Step 3: Re-apply the preferred currency when Settings closes**

Replace the Settings sheet (currently line 58):

```swift
        .sheet(isPresented: $showSettings) { SettingsView() }
```

with:

```swift
        .sheet(isPresented: $showSettings, onDismiss: {
            // Adopt a changed preferred currency: update the new-expense default + dashboard display
            // currency, and reload Home only when it actually changed.
            let preferred = SharedSummary().readPreferredCurrency()
            let changed = recentModel.currency != preferred
            quickAddModel.currency = preferred
            recentModel.currency = preferred
            if changed { Task { await recentModel.load() } }
        }) { SettingsView() }
```

- [ ] **Step 4: Build the app for the simulator**

Run:
```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath AppProject/.build build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run the full unit suite (nothing regressed)**

Run: `swift test`
Expected: PASS — all prior tests plus Tasks 1–2's new ones.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoFeatures/RootView.swift
git commit -m "feat(features): default Quick Add + dashboard to the preferred currency"
```

---

## Task 6: Runtime verification + review

**Files:** none (verification only).

- [ ] **Step 1: Launch in the simulator and screenshot the picker**

```bash
APP="$(find AppProject/.build/Build/Products -name 'Goldengo.app' -path '*Debug-iphonesimulator*' | head -1)"
xcrun simctl boot "iPhone 17" 2>/dev/null || true
xcrun simctl install booted "$APP"
SIMCTL_CHILD_GOLDENGO_SEED_SAMPLE=1 xcrun simctl launch booted com.goldengo.app
xcrun simctl openurl booted goldengo://settings
xcrun simctl io booted screenshot /tmp/gol66-settings.png
```
Open `/tmp/gol66-settings.png`; confirm the "Currency" row shows "L · Albanian Lek" and tapping (on device) opens the Suggested + All searchable list.

- [ ] **Step 2: Verify persistence + propagation**

The sim can't drive taps, so set the preference via the App-Group store and relaunch to confirm it's
read back and applied:
```bash
GRP="$(xcrun simctl get_app_container booted com.goldengo.app group.com.goldengo.app)"
/usr/libexec/PlistBuddy -c "Set :preferredCurrency EUR" "$GRP/Library/Preferences/group.com.goldengo.app.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :preferredCurrency string EUR" "$GRP/Library/Preferences/group.com.goldengo.app.plist"
xcrun simctl terminate booted com.goldengo.app 2>/dev/null
xcrun simctl launch booted com.goldengo.app
xcrun simctl openurl booted goldengo://quickadd
xcrun simctl io booted screenshot /tmp/gol66-quickadd-eur.png
```
Confirm Quick Add now shows the euro symbol and the keypad offers "." (euro has a minor unit). Capture
os_log for AttributeGraph cycles / "modifying state" / hangs:
```bash
xcrun simctl spawn booted log show --last 40s --predicate 'process == "Goldengo"' --style compact | grep -iE 'AttributeGraph|modifying state|cycle detected|hang|fatal'
```
Expected: empty (no cycles/hangs).

- [ ] **Step 3: Device tap-test (gestures the sim can't drive)**

Build + install on the paired iPhone (13 Pro Max) so the user can confirm: Settings → Currency → pick
euro (Suggested) and a searched currency, return, and see Quick Add default to it. (Device build per
CLAUDE.md: add `-destination 'generic/platform=iOS' -allowProvisioningUpdates`, then
`xcrun devicectl device install app`.) The user unlocks + opens the app.

- [ ] **Step 4: Second-Opus review**

Dispatch a general-purpose Opus 4.8 reviewer over `git diff main...HEAD` for GOL-66. Focus:
App-Group key correctness, Sendable/MainActor, no iOS-only API on the macOS build, the `@State`
ownership change for `quickAddModel` (no behavior regression vs the prior inline model), search-filter
intent (Rule 9), `GoldengoTheme` match. Fix findings; re-run `swift test`.

- [ ] **Step 5: Final green gate**

Run: `swift test`
Expected: PASS. Branch ready to ff-merge to `main`.

---

## Self-Review

**1. Spec coverage:**
- Persisted preferred currency (App Group, default lek) → Task 1. ✓
- Searchable picker, Suggested + All, Locale names, rate-table universe minus non-currencies → Tasks 2 (catalog), 3 (picker). ✓
- Settings "Currency" section showing the current default → Task 4. ✓
- Drives Quick Add default + dashboard display currency; re-applies on change → Task 5. ✓
- Tests: SharedSummary round-trip/default + pure filter/selectable → Tasks 1, 2; UI build+runtime+device → Tasks 3–6. ✓
- Scoping note (dashboard conversion is GOL-68) → respected: Task 5 only sets `recentModel.currency` (single-currency), no conversion added. ✓
- Second-Opus review + runtime os_log/screenshot/device → Task 6. ✓

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N". The picker code is a complete baseline; `/frontend-design` polish is an explicit, bounded step, not an undecided placeholder.

**3. Type consistency:** `SharedSummary.preferredCurrencyKey` / `readPreferredCurrency()` / `setPreferredCurrency(_:)`, `CurrencyCatalog.selectable(from:)` / `.filter(_:query:name:)`, `CurrencyPickerView(available:selectedCode:)`, `CurrencyCode.popular`/`.symbol`/`.rawValue`, `RecentExpensesModel.currency` (var), `QuickAddModel(store:currency:)` — all used consistently across tasks and match the existing signatures read from the codebase.
