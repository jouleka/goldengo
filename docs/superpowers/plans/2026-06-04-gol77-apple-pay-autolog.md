# Apple Pay auto-log (GOL-77) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a silent `LogPaymentIntent` (an iOS Shortcuts action) that an Apple Pay **Transaction automation** feeds the tapped amount + merchant into, auto-adding an expense to Goldengo — plus an in-app setup guide.

**Architecture:** The intent reuses the existing `ExpenseLogging.log` → `logManual` path (so it gets merchant→category auto-categorization, subscription detection, preferred currency, widget refresh — no new persistence). It lives in the **existing** app-target file `QuickLogShortcut.swift` (App Shortcut/Intent placement rule from GOL-73; no new app-target file → no `project.rb` regeneration → signing stays intact). The setup card mirrors GOL-76.

**Tech Stack:** Swift 6, App Intents, SwiftUI, SwiftData, XCTest. `swift test` (also macOS CI) for the reused logic; `xcodebuild` for the app target / device.

**Branch:** `feature/gol-77-apple-pay-autolog` (created; spec committed).

---

## File structure

**Modify (Tests):** `Tests/GoldengoIntentsTests/ExpenseLoggingTests.swift` — pin the auto-capture contract.
**Modify (Sources):** `AppProject/Goldengo/QuickLogShortcut.swift` — add `LogPaymentIntent`.
**Modify (Sources):** `Sources/GoldengoFeatures/Settings/SettingsView.swift` — add the "Apple Pay auto-log" setup card.

No `project.rb` change (no new files); no model/persistence change (reuses `logManual`).

---

## Task 1: Pin the auto-capture logging contract

The new intent relies on `ExpenseLogging.log(merchant:, categoryName: nil)` keeping the merchant name and defaulting an unrecognized merchant to "Other". That behavior already exists in `logManual`; this test pins it through the `ExpenseLogging.log` entry point so a future change can't silently break auto-capture. (It passes against the current code — a characterization test, not red-first.)

**Files:**
- Modify: `Tests/GoldengoIntentsTests/ExpenseLoggingTests.swift`

- [ ] **Step 1: Add the test**

Add inside the `ExpenseLoggingTests` class (before the closing brace):

```swift
    func test_log_unknownMerchant_keepsMerchant_andCategorizesOther() async throws {
        // An auto-captured Apple Pay payment passes a merchant and no category. The merchant must be
        // kept (it labels the Recent row and feeds subscription detection) and an unrecognised merchant
        // must land in a real "Other" category — never silently uncategorized.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = try await ExpenseLogging.log(amount: 350, currencyCode: "ALL",
                                                   merchant: "Tiny Cafe", categoryName: nil, store: store)
        let snap = try await store.recentExpenses().first
        XCTAssertEqual(snap?.merchantName, "Tiny Cafe")
        XCTAssertEqual(snap?.categoryName, "Other")
        XCTAssertTrue(summary.contains("350"))
    }
```

- [ ] **Step 2: Run it (expected PASS — pins existing behavior)**

Run: `swift test --filter ExpenseLoggingTests`
Expected: PASS (all `ExpenseLoggingTests`, including this one — the merchant/`Other` logic already lives in `logManual`).

- [ ] **Step 3: Commit**

```bash
git add Tests/GoldengoIntentsTests/ExpenseLoggingTests.swift
git commit -m "test(gol-77): pin auto-capture contract (keep merchant, unknown -> Other)"
```

---

## Task 2: Add `LogPaymentIntent` (the silent Shortcuts action)

**Files:**
- Modify: `AppProject/Goldengo/QuickLogShortcut.swift`

No unit test (App Intent + automation = OS runtime, device-verified; the save logic is covered by Task 1 + existing tests).

- [ ] **Step 1: Add the intent**

In `AppProject/Goldengo/QuickLogShortcut.swift`, insert this **before** the `GoldengoAppShortcuts` struct (i.e. after `LogExpenseIntent`'s closing brace):

```swift
/// A silent action wired into an iOS "Transaction" Personal Automation: every in-store Apple Pay tap
/// feeds it the amount (+ merchant) and it logs the expense without opening the app. A plain AppIntent
/// (not an AppShortcut) so it appears in the Shortcuts action picker. Reuses ExpenseLogging.log →
/// merchant auto-categorizes (learned mapping → "Other") and feeds subscription detection.
@available(iOS 17.0, *)
struct LogPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Payment"
    static let description = IntentDescription("Add a payment to Goldengo — wire this to an Apple Pay Transaction automation.")

    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Merchant") var merchant: String?

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Log a \(\.$amount) payment from \(\.$merchant)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = GoldengoStore.shared()
        let preferred = SharedSummary().readPreferredCurrency()
        var raw = Decimal(amount), amt = Decimal()
        NSDecimalRound(&amt, &raw, preferred.fractionDigits, .plain)   // currency-precise; no float artifacts
        let m = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await ExpenseLogging.log(amount: amt, currencyCode: preferred.rawValue,
                                         merchant: (m?.isEmpty ?? true) ? nil : m, categoryName: nil, store: store)
        return .result()   // silent — the automation runs with no notification, no app launch
    }
}
```

- [ ] **Step 2: Build for macOS (CI surface) and the iOS simulator**

Run: `swift build`
Expected: succeeds (the file already imports `AppIntents`/`Foundation`/`GoldengoData`/`GoldengoCore`/`GoldengoIntents`; `NSDecimalRound` is Foundation).

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Verify the action is in the app's App-Intents metadata**

Run:
```bash
strings -a AppProject/.build/Build/Products/Debug-iphonesimulator/Goldengo.app/Metadata.appintents/extract.actionsdata | grep -o 'LogPaymentIntent'
```
Expected: prints `LogPaymentIntent` (so it'll appear as a "Log Payment" action in Shortcuts). If empty, the intent wasn't extracted — stop and investigate.

- [ ] **Step 4: Commit**

```bash
git add AppProject/Goldengo/QuickLogShortcut.swift
git commit -m "feat(gol-77): LogPaymentIntent — silent action for the Apple Pay Transaction automation"
```

---

## Task 3: Settings — "Apple Pay auto-log" setup card

**Files:**
- Modify: `Sources/GoldengoFeatures/Settings/SettingsView.swift`

No unit test (SwiftUI Form section; verified by build + the Settings deep-link screenshot). `@Environment(\.openURL)` already exists on the view (added in GOL-76).

- [ ] **Step 1: Add the section**

In `SettingsView.swift`, insert this **after** the `Section("Quick-log gesture") { … }` block and **before** `Section("Privacy")`:

```swift
                Section("Apple Pay auto-log") {
                    Text("Auto-add an expense every time you tap to pay in a store — set up an iOS automation once:")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        Label("Open Shortcuts", systemImage: "creditcard")
                    }
                    Label("Shortcuts → **Automation** tab → **＋** → **Transaction** → pick your card(s) → **Run Immediately** (turn off Notify).", systemImage: "1.circle.fill")
                    Label("**Add Action** → search **Log Payment** → set **Amount** to the transaction's Amount (and **Merchant** to its Merchant) → Done.", systemImage: "2.circle.fill")
                    Text("In-store taps only — online/web Apple Pay can't trigger it (use Import for those). iOS won't let an app set this up for you.")
                        .font(.caption).foregroundStyle(.secondary)
                }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Runtime check in the simulator (optional but quick)**

```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build >/dev/null 2>&1
xcrun simctl install booted AppProject/.build/Build/Products/Debug-iphonesimulator/Goldengo.app
xcrun simctl launch booted com.goldengo.app >/dev/null 2>&1
xcrun simctl openurl booted goldengo://settings
xcrun simctl io booted screenshot /tmp/settings-applepay.png
```
Expected: the "Apple Pay auto-log" section renders (Open Shortcuts button + the two steps + caveat), markdown bold intact.

- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoFeatures/Settings/SettingsView.swift
git commit -m "feat(gol-77): Settings 'Apple Pay auto-log' setup card"
```

---

## Task 4: Full verification, device, review, handoff

- [ ] **Step 1: Full test suite green**

Run: `swift test`
Expected: all pass (the prior baseline + the new auto-capture pin test), zero skipped.

- [ ] **Step 2: Device build + install**

```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath AppProject/.build-device build
xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E AppProject/.build-device/Build/Products/Debug-iphoneos/Goldengo.app
```
Expected: BUILD SUCCEEDED + `App installed`. (No `project.rb` regeneration was needed, so signing is intact.)

- [ ] **Step 3: On-device test (user)**

Ask the user to: open **Settings → Apple Pay auto-log**, create the Transaction automation per the steps (Transaction → Run Immediately → Add Action → **Log Payment** → map Amount + Merchant), then **tap to pay in a store**. Confirm the expense appears in Goldengo (correct amount, merchant, preferred currency; categorized or "Other"), with **no app launch and no per-payment prompt**. (Simulator has no Apple Pay/Transaction trigger — device-only.)

- [ ] **Step 4: Second-Opus review**

Dispatch a fresh general-purpose reviewer (model: opus) over `git diff main...HEAD`; fix real findings, re-run `swift test`.

- [ ] **Step 5: Merge + ticket**

On the user's go: `git checkout main && git merge --ff-only feature/gol-77-apple-pay-autolog && git push`. Set GOL-77 → **To Verify** with a summary comment.

---

## Self-review

**Spec coverage** (against `2026-06-04-gol77-apple-pay-autolog-design.md`):
- §Component 1 `LogPaymentIntent` (amount + optional merchant, round, silent, reuse `ExpenseLogging.log`) → Task 2. ✓
- §Component 2 Settings "Apple Pay auto-log" card → Task 3. ✓
- §Tests (merchant kept + unknown→Other; intent/automation device-verified) → Task 1 + Task 4 Step 3. ✓
- §Data flow (tap → automation → action → logManual → Home auto-refresh) → Tasks 2/4. ✓
- §Out of scope (FinanceKit, online, dedup, no new ExpenseSource, no automation creation) → honored; no such tasks. ✓

**Placeholder scan:** none — every code step shows complete code; commands have expected output; the metadata grep is a concrete gate.

**Type consistency:** `ExpenseLogging.log(amount: Decimal, currencyCode: String, merchant: String?, categoryName: String?, store:)` is called identically in Task 1 (test) and Task 2 (intent). `LogPaymentIntent` exposes `amount: Double` + `merchant: String?`; `parameterSummary` references `\(\.$amount)`/`\(\.$merchant)` matching the declared parameters. `NSDecimalRound(_:_:_:_:)` + `SharedSummary().readPreferredCurrency()` (→ `CurrencyCode`, `.rawValue`/`.fractionDigits`) match the GOL-73 `LogExpenseIntent` usage already in the same file. The Settings section reuses the existing `@Environment(\.openURL)`.
