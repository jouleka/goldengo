# Quick-log expense via App Intent (GOL-73) Implementation Plan

> **Superseded during implementation** — the shipped feature uses a category tap-list, the intent lives in the app target (App Shortcuts can't register from a package), and the result is silent (no dialog). This early plan describes the note+amount approach; see the GOL-73 commits for the final shape.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user log an expense from a trigger of their choice — two system prompts ("What's it for?" then "Amount?") — saved in the preferred currency without opening the app.

**Architecture:** Extend the existing background `LogExpenseIntent` (App Intents) and its shared `ExpenseLogging.log` save path. The note (the "what") is wired to the `logManual(note:)` built in GOL-70/71. The save logic is unit-tested in `GoldengoIntentsTests`; the intent's parameter-prompt UI and the user's trigger binding are App-Intents/OS runtime behavior, verified on device. The action is exposed via the existing `AppShortcut`, so iOS surfaces it for any trigger — we hardcode none.

**Tech Stack:** Swift 6, App Intents, SwiftData, XCTest. `swift test` (also macOS CI) for the logic; `xcodebuild` for the device build.

**Branch:** `feature/gol-73-quick-log-intent` (created; spec committed; GOL-73 In Progress).

---

## File structure

**Modify (Sources):**
- `Sources/GoldengoIntents/ExpenseLogging.swift` — add `note` to the shared `log` path + confirmation string
- `Sources/GoldengoIntents/LogExpenseIntent.swift` — params become note + amount, drop category, preferred currency

**Modify (Tests):**
- `Tests/GoldengoIntentsTests/ExpenseLoggingTests.swift` — note round-trip + blank-note confirmation

**Modify (Docs):**
- `README.md` — a "Quick-log (one gesture)" section listing trigger options

No `AppProject/project.rb` change (no new files in the app target). `GoldengoShortcuts.swift` is unchanged — it already exposes the action for binding.

---

## Task 1: `note` in the shared `ExpenseLogging.log` path

**Files:**
- Modify: `Sources/GoldengoIntents/ExpenseLogging.swift:7-13`
- Test: `Tests/GoldengoIntentsTests/ExpenseLoggingTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/GoldengoIntentsTests/ExpenseLoggingTests.swift` (inside the class, before the closing brace):

```swift
    func test_logExpense_persistsNote_andIncludesItInConfirmation() async throws {
        // The note captured at the trigger must reach the saved expense (the whole point of the
        // feature), and the confirmation must echo it so the user knows what was logged without
        // ever opening the app.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = try await ExpenseLogging.log(amount: 500, currencyCode: "ALL",
                                                   merchant: nil, note: "coffee", categoryName: nil, store: store)
        let rows = try await store.recentExpenses()
        XCTAssertEqual(rows.first?.note, "coffee")
        XCTAssertTrue(summary.contains("coffee"))
    }

    func test_logExpense_blankNote_storesNilAndPlainConfirmation() async throws {
        // A blank/whitespace note normalizes to nil (so the Recent row falls back cleanly) and must
        // not leave a dangling "— " in the confirmation.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = try await ExpenseLogging.log(amount: 500, currencyCode: "ALL",
                                                   merchant: nil, note: "   ", categoryName: nil, store: store)
        let rows = try await store.recentExpenses()
        XCTAssertNil(rows.first?.note)
        XCTAssertFalse(summary.contains("—"))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ExpenseLoggingTests`
Expected: FAIL — compile error (`extra argument 'note' in call`).

- [ ] **Step 3: Add `note` to `ExpenseLogging.log`**

Replace `ExpenseLogging.swift:7-13` (the whole `log` function). Add `note: String? = nil` after
`merchant:` (defaulted so the existing `test_logExpense_persistsThroughStore` keeps compiling), forward
it to `logManual`, and append it to the confirmation only when non-blank:

```swift
    public static func log(amount: Decimal, currencyCode: String, merchant: String?,
                           note: String? = nil, categoryName: String?, store: IngestionStore) async throws -> String {
        let currency = CurrencyCode(currencyCode)
        try await store.logManual(amount: amount, currency: currency,
                                  merchant: merchant, note: note, categoryName: categoryName)
        let money = Money(amount: amount, currency: currency).formatted()
        let clean = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean?.isEmpty ?? true) ? "Logged \(money)" : "Logged \(money) — \(clean!)"
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ExpenseLoggingTests`
Expected: PASS (all three — the new two plus the existing `test_logExpense_persistsThroughStore`).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoIntents/ExpenseLogging.swift Tests/GoldengoIntentsTests/ExpenseLoggingTests.swift
git commit -m "feat(gol-73): carry a note through the shared ExpenseLogging.log path"
```

---

## Task 2: `LogExpenseIntent` — note + amount only, preferred currency

**Files:**
- Modify: `Sources/GoldengoIntents/LogExpenseIntent.swift:13-31`

No unit test (App Intent parameter prompts + the no-app-launch behavior are OS runtime, verified on device). The save logic it calls is covered by Task 1.

- [ ] **Step 1: Confirm nothing references the `category` parameter being removed**

Run: `grep -rn "LogExpenseIntent" Sources/ AppProject/`
Expected: only the definition (`LogExpenseIntent.swift`) and `GoldengoShortcuts.swift` constructing `LogExpenseIntent()` with no arguments. No reference to `.category`. (If anything sets `.category`, stop and reconcile.)

- [ ] **Step 2: Rewrite the intent's parameters, summary, and perform()**

Replace `LogExpenseIntent.swift:13-31` (the `struct LogExpenseIntent` body — keep the `IntentEnvironment` enum above it unchanged):

```swift
@available(iOS 17.0, macOS 14.0, *)
public struct LogExpenseIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Expense"
    public static let description = IntentDescription("Quickly log an expense in Goldengo without opening the app.")

    @Parameter(title: "What's it for?") public var note: String
    @Parameter(title: "Amount") public var amount: Double

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$note) for \(\.$amount)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = IntentEnvironment.storeProvider?() else {
            return .result(dialog: "Goldengo isn't ready yet.")
        }
        let currency = SharedSummary().readPreferredCurrency().rawValue
        let summary = try await ExpenseLogging.log(amount: Decimal(amount), currencyCode: currency,
                                                   merchant: nil, note: note, categoryName: nil, store: store)
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}
```

- [ ] **Step 3: Build to verify it compiles (incl. the macOS/CI surface)**

Run: `swift build`
Expected: build succeeds. (`note: String` is non-optional so iOS prompts for it; `SharedSummary` and `CurrencyCode` come from `GoldengoData`/`GoldengoCore`, already dependencies of `GoldengoIntents`.)

- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoIntents/LogExpenseIntent.swift
git commit -m "feat(gol-73): LogExpenseIntent prompts note + amount, saves in preferred currency"
```

---

## Task 3: README — "Quick-log (one gesture)" trigger options

**Files:**
- Modify: `README.md`

No test (docs).

- [ ] **Step 1: Add the section**

Read `README.md`, then add this section after the "Running on your iPhone…" / iCloud section (a sensible spot near the device usage docs):

```markdown
## Quick-log (one gesture)

Log an expense without opening the app: bind **"Log Expense"** to any trigger you like, then it asks
*"What's it for?"* and *"Amount?"* and saves to your default currency.

Goldengo exposes the action via App Shortcuts, so attach it to whichever you prefer:
- **Back Tap** — Settings → Accessibility → Touch → **Back Tap** → Double or Triple Tap → **Log Expense**
- **Action Button** (iPhone 15 Pro and later) — Settings → **Action Button** → Shortcut → **Log Expense**
- **Control Center**, a **Home/Lock-Screen widget**, or **Siri** ("Log an expense in Goldengo")

The app never opens — you get a quick confirmation, and the expense is in Recent next time you open it.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(gol-73): document quick-log trigger options"
```

---

## Task 4: Full verification, device, review, handoff

No code unless verification surfaces a defect (then fix TDD-style and re-run).

- [ ] **Step 1: Full test suite green**

Run: `swift test`
Expected: all pass (the 190 baseline + the 2 new note tests = 192), zero skipped.

- [ ] **Step 2: Device build + install**

```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath AppProject/.build-device build
xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E AppProject/.build-device/Build/Products/Debug-iphoneos/Goldengo.app
```
Expected: BUILD SUCCEEDED + `App installed`.

- [ ] **Step 3: On-device tap-test (user)**

Ask the user to bind a trigger (e.g. Settings → Accessibility → Touch → Back Tap → Double Tap → **Log Expense**, or the Action Button) and run it. Confirm: iOS prompts **"What's it for?" then "Amount?"** (note-first order), the **app does not open**, the confirmation shows amount + note, and the expense appears in **Recent** (correct note, preferred currency, "Other" category) on next open. **If the prompt order is amount-first**, adjust the `parameterSummary` / parameter declaration order in `LogExpenseIntent` until it is note → amount, rebuild, re-test.

- [ ] **Step 4: Second-Opus review**

Dispatch a fresh general-purpose reviewer (model: opus) over `git diff main...HEAD`; fix real findings (TDD where logic), re-run `swift test`.

- [ ] **Step 5: Merge + ticket**

On the user's go: `git checkout main && git merge --ff-only feature/gol-73-quick-log-intent && git push`. Set GOL-73 → **To Verify** with a summary comment.

---

## Self-review

**Spec coverage** (against `2026-06-03-gol73-quick-log-intent-design.md`):
- §1 `ExpenseLogging.log` note + confirmation → Task 1. ✓
- §2 `LogExpenseIntent` note+amount, drop category, preferred currency, parameterSummary → Task 2. ✓
- §3 `AppShortcut` unchanged → no task needed (verified untouched in Task 2 Step 1). ✓
- §4 README trigger options → Task 3. ✓
- Tests (note round-trip, blank→nil, confirmation) → Task 1. ✓
- Device/runtime verification + note-first prompt order → Task 4 Step 3. ✓
- Out of scope (no popup, no trigger config, no project.rb) → honored. ✓

**Placeholder scan:** none — every code step shows complete code; the README content is given verbatim; commands have expected output. The "adjust if amount-first" branch in Task 4 is a real, bounded contingency, not a placeholder.

**Type consistency:** `ExpenseLogging.log(amount:currencyCode:merchant:note:categoryName:store:)` with `note: String? = nil` is used identically in Task 1's tests/impl and Task 2's `perform()`. `LogExpenseIntent` exposes `note: String` + `amount: Double` (category removed); `SharedSummary().readPreferredCurrency().rawValue` yields the `String` that `log(currencyCode:)` expects. `parameterSummary` references `\(\.$note)` and `\(\.$amount)` matching the declared parameters. Consistent.
