# Richer expense details (GOL-70 + GOL-71) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional free-text **note** to expenses — one field at add time on the Quick Add keypad screen, both merchant and note at edit time — and surface the note in the Recent row.

**Architecture:** The note is backed by the **already-existing** `ExpenseRecord.note` column (no SwiftData migration). Pure/data plumbing (snapshot, `logManual`, `updateExpense`, a `displayTitle` label helper) is built TDD with XCTest against an in-memory store. SwiftUI view wiring (Quick Add note row, Edit field, Recent row text) is verified by build + simulator + the user's device tap-test, per project convention. New `note:` parameters are defaulted (`= nil`) on concrete methods so existing callers (`GoldengoIntents`, app seed, tests) keep compiling; only the two paths that actually carry a note (`QuickAddModel`, `RecentExpensesModel`) pass it.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SwiftData, XCTest. Tests run headless via `swift test` (also the macOS CI gate); the app builds via `xcodebuild` for the iOS simulator/device.

**Branch:** `feature/gol-70-71-expense-details` (already created; spec committed).

---

## File structure

**Modify (Sources):**
- `Sources/GoldengoData/IngestionStore.swift` — `ExpenseSnapshot.note`, `displayTitle`, `makeSnapshot`, `logManual`
- `Sources/GoldengoData/IngestionStore+Editing.swift` — `updateExpense` note param
- `Sources/GoldengoData/RecentExpensesReading.swift` — protocol `updateExpense` signature
- `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift` — `update(...)` wrapper note param
- `Sources/GoldengoFeatures/Recent/EditExpenseView.swift` — note `@State` + section + `onSave`
- `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift` — edit `onSave` closure, row text, undo toast
- `Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift` — `note` property
- `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift` — note row + keyboard handling

**Modify (Tests):**
- `Tests/GoldengoDataTests/LogManualTests.swift` — note round-trips / blank→nil
- `Tests/GoldengoDataTests/ExpenseEditingTests.swift` — `updateExpense` sets/clears note
- `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift` — `FailingReader` fake gains note param
- `Tests/GoldengoFeaturesTests/QuickAddModelTests.swift` — typed note reaches the saved expense

**Create (Tests):**
- `Tests/GoldengoDataTests/ExpenseSnapshotTests.swift` — `displayTitle` precedence

No `AppProject/project.rb` change (no new files in the app target; new test file lives inside the package).

---

## Task 1: Carry `note` through the snapshot and `logManual`

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift:7-20` (struct), `:98-103` (makeSnapshot), `:119-137` (logManual)
- Test: `Tests/GoldengoDataTests/LogManualTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/GoldengoDataTests/LogManualTests.swift` (inside the `LogManualTests` class, before the closing brace):

```swift
    func test_logManual_persistsNote_roundTripsToSnapshot() async throws {
        // The note typed at add time must survive to the snapshot, or the Recent row and Edit view
        // have nothing to show — this is the whole point of the feature.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let key = try await store.logManual(amount: 250, currency: .all, merchant: nil,
                                            note: "lunch with Ana", categoryName: nil)
        let snap = try await store.snapshot(dedupeKey: key)
        XCTAssertEqual(snap?.note, "lunch with Ana")
    }

    func test_logManual_blankNote_storesNil() async throws {
        // A whitespace-only note normalizes to nil so the Recent row falls back to merchant/category
        // instead of rendering a blank primary line.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let key = try await store.logManual(amount: 100, currency: .all, merchant: nil,
                                            note: "   ", categoryName: nil)
        let snap = try await store.snapshot(dedupeKey: key)
        XCTAssertNil(snap?.note)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter LogManualTests`
Expected: FAIL — compile error (`logManual` has no `note:` parameter; `ExpenseSnapshot` has no `note`).

- [ ] **Step 3: Add `note` to `ExpenseSnapshot`**

In `Sources/GoldengoData/IngestionStore.swift`, in the `ExpenseSnapshot` struct, add `note` right after `merchantName`:

```swift
    public var merchantName: String?
    public var note: String?
    public var kind: TransactionKind
```

- [ ] **Step 4: Carry `note` in `makeSnapshot`**

Replace the body of `makeSnapshot` (`:98-103`) so it passes `r.note` (between `merchantName` and `kind`, matching the struct's declaration order):

```swift
    private func makeSnapshot(_ r: ExpenseRecord) -> ExpenseSnapshot {
        ExpenseSnapshot(dedupeKey: r.dedupeKey, amount: r.amount, currencyCode: r.currencyCode,
                        source: r.source, categoryName: r.category?.name,
                        date: r.date, merchantName: r.merchantName, note: r.note, kind: r.kind,
                        subscriptionName: r.subscription?.displayName)
    }
```

- [ ] **Step 5: Add the `note` parameter to `logManual`**

Replace the signature and record construction in `logManual` (`:119-124`). Add `note: String? = nil` after `merchant:`, normalize it (trim, empty→nil), and pass it into the `ExpenseRecord` initializer:

```swift
    @discardableResult
    public func logManual(amount: Decimal, currency: CurrencyCode,
                          merchant: String?, note: String? = nil, categoryName: String?) throws -> String {
        let key = "manual:\(UUID().uuidString)"
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rec = ExpenseRecord(amount: amount, currencyCode: currency.rawValue, date: .now,
                                merchantName: merchant, note: (cleanNote?.isEmpty ?? true) ? nil : cleanNote,
                                kind: .expense, source: .manual, dedupeKey: key)
```

(Leave the rest of `logManual` — category assignment, insert, link, save, `refreshSharedTodayTotal`, `return key` — unchanged.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter LogManualTests`
Expected: PASS (all `LogManualTests`, including the two new ones).

- [ ] **Step 7: Commit**

```bash
git add Sources/GoldengoData/IngestionStore.swift Tests/GoldengoDataTests/LogManualTests.swift
git commit -m "feat(gol-70-71): carry an optional note through snapshot + logManual"
```

---

## Task 2: `ExpenseSnapshot.displayTitle` (row label precedence)

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift` (`ExpenseSnapshot` struct)
- Create: `Tests/GoldengoDataTests/ExpenseSnapshotTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoDataTests/ExpenseSnapshotTests.swift`:

```swift
import XCTest
import GoldengoCore
@testable import GoldengoData

final class ExpenseSnapshotTests: XCTestCase {
    /// Build a snapshot overriding only the three fields that drive the row label.
    private func snap(note: String? = nil, merchant: String? = nil, category: String? = nil) -> ExpenseSnapshot {
        ExpenseSnapshot(dedupeKey: "k", amount: 1, currencyCode: "ALL", source: .manual,
                        categoryName: category, date: .now, merchantName: merchant, note: note,
                        kind: .expense, subscriptionName: nil)
    }

    func test_displayTitle_prefersNoteThenMerchantThenCategoryThenFallback() {
        // The Recent row must lead with the most specific label the user gave: the note ("what was
        // bought") wins over the merchant ("who"), which wins over the category, with a generic
        // fallback only when nothing is set. This is the contract the row and undo toast rely on.
        XCTAssertEqual(snap(note: "lunch with Ana", merchant: "Joe's", category: "Food").displayTitle,
                       "lunch with Ana")
        XCTAssertEqual(snap(merchant: "Netflix", category: "Bills").displayTitle, "Netflix")
        XCTAssertEqual(snap(category: "Groceries").displayTitle, "Groceries")
        XCTAssertEqual(snap().displayTitle, "Expense")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ExpenseSnapshotTests`
Expected: FAIL — compile error (`ExpenseSnapshot` has no member `displayTitle`).

- [ ] **Step 3: Add the `displayTitle` computed property**

In `Sources/GoldengoData/IngestionStore.swift`, inside `ExpenseSnapshot`, add directly after the existing `id` computed property:

```swift
    /// The row's primary label: lead with the most specific thing the user gave — the free-text note
    /// ("what"), then the merchant ("who"), then the category, then a generic fallback.
    public var displayTitle: String { note ?? merchantName ?? categoryName ?? "Expense" }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ExpenseSnapshotTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/IngestionStore.swift Tests/GoldengoDataTests/ExpenseSnapshotTests.swift
git commit -m "feat(gol-71): ExpenseSnapshot.displayTitle (note → merchant → category)"
```

---

## Task 3: `updateExpense` persists an optional note (protocol + impl + model)

**Files:**
- Modify: `Sources/GoldengoData/RecentExpensesReading.swift:13` (protocol)
- Modify: `Sources/GoldengoData/IngestionStore+Editing.swift:28-44` (impl)
- Modify: `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift:52-58` (wrapper)
- Modify: `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift:36` (fake)
- Test: `Tests/GoldengoDataTests/ExpenseEditingTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/GoldengoDataTests/ExpenseEditingTests.swift` (inside the class, before the closing brace):

```swift
    func test_updateExpense_setsAndClearsNote() async throws {
        // Editing must be able to add a note and later remove it (blank → nil) — not just change it —
        // so a mistaken note isn't permanent.
        let store = try makeStore()
        let key = try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")

        try await store.updateExpense(dedupeKey: key, amount: 250, merchant: "Coffee",
                                      note: "with Ana", categoryName: "Coffee", date: .now)
        var snap = try await store.snapshot(dedupeKey: key)
        XCTAssertEqual(snap?.note, "with Ana")

        try await store.updateExpense(dedupeKey: key, amount: 250, merchant: "Coffee",
                                      note: "   ", categoryName: "Coffee", date: .now)
        snap = try await store.snapshot(dedupeKey: key)
        XCTAssertNil(snap?.note)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ExpenseEditingTests`
Expected: FAIL — compile error (`updateExpense` has no `note:` parameter).

- [ ] **Step 3: Add `note` to the protocol requirement**

In `Sources/GoldengoData/RecentExpensesReading.swift`, replace line 13 (protocols can't carry default values, so no `= nil` here):

```swift
    func updateExpense(dedupeKey: String, amount: Decimal, merchant: String?, note: String?, categoryName: String?, date: Date) async throws
```

- [ ] **Step 4: Implement `note` in the concrete `updateExpense`**

In `Sources/GoldengoData/IngestionStore+Editing.swift`, replace the doc comment and method (`:28-44`). Add `note: String? = nil` after `merchant:` (the default keeps direct callers like `ExpenseEditingTests` compiling), and normalize it the same way merchant is:

```swift
    /// Edit an existing expense's amount, merchant, note, category, and date. An empty/whitespace
    /// merchant, note, or category clears that field.
    public func updateExpense(dedupeKey: String, amount: Decimal, merchant: String?,
                              note: String? = nil, categoryName: String?, date: Date) throws {
        guard let r = try fetchActiveExpense(dedupeKey: dedupeKey) else { return }
        r.amount = amount
        let trimmedMerchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        r.merchantName = (trimmedMerchant?.isEmpty ?? true) ? nil : trimmedMerchant
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        r.note = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
        r.date = date
        if let categoryName, !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            r.category = try findOrCreateCategory(named: categoryName)
        } else {
            r.category = nil
        }
        r.updatedAt = .now
        try modelContext.save()
    }
```

- [ ] **Step 5: Update the `FailingReader` fake to match the protocol**

In `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift`, replace line 36:

```swift
    func updateExpense(dedupeKey: String, amount: Decimal, merchant: String?, note: String?, categoryName: String?, date: Date) async throws { throw Boom() }
```

- [ ] **Step 6: Thread `note` through `RecentExpensesModel.update`**

In `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift`, replace `update(...)` (`:52-58`). Add `note: String? = nil` (defaulted so the view, not yet updated, still compiles) and forward it:

```swift
    /// Apply an edit to an expense, then reload so the change is reflected.
    public func update(_ snapshot: ExpenseSnapshot, amount: Decimal, merchant: String?,
                       note: String? = nil, categoryName: String?, date: Date) async {
        try? await reader.updateExpense(dedupeKey: snapshot.dedupeKey, amount: amount,
                                        merchant: merchant, note: note, categoryName: categoryName, date: date)
        await load()
    }
```

- [ ] **Step 7: Run the affected suites to verify green**

Run: `swift test --filter ExpenseEditingTests` then `swift test --filter RecentExpensesModelTests`
Expected: PASS (the new note test passes; the existing reader/fake tests still compile and pass).

- [ ] **Step 8: Commit**

```bash
git add Sources/GoldengoData/RecentExpensesReading.swift Sources/GoldengoData/IngestionStore+Editing.swift Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift Tests/GoldengoDataTests/ExpenseEditingTests.swift Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift
git commit -m "feat(gol-71): updateExpense persists an optional note"
```

---

## Task 4: Edit a note in `EditExpenseView`

**Files:**
- Modify: `Sources/GoldengoFeatures/Recent/EditExpenseView.swift`
- Modify: `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift:78-87`

No unit test (SwiftUI view wiring — verified by build + runtime + device).

- [ ] **Step 1: Widen the `onSave` closure type**

In `EditExpenseView.swift`, replace the `onSave` property declaration (line 14):

```swift
    private let onSave: (_ amount: Decimal, _ merchant: String?, _ note: String?, _ category: String?, _ date: Date) -> Void
```

and the `onSave` parameter in `init` (line 29):

```swift
                onSave: @escaping (_ amount: Decimal, _ merchant: String?, _ note: String?, _ category: String?, _ date: Date) -> Void,
```

- [ ] **Step 2: Add note state and initialize it**

In `EditExpenseView.swift`, add a `note` state var after `merchant` (line 18):

```swift
    @State private var merchant: String
    @State private var note: String
```

and initialize it in `init` after the `_merchant` line (line 36):

```swift
        _merchant = State(initialValue: snapshot.merchantName ?? "")
        _note = State(initialValue: snapshot.note ?? "")
```

- [ ] **Step 3: Add the note section and place it after merchant**

In `EditExpenseView.swift`, add the section between `merchantSection` and `categorySection` in the `Form` (line 59):

```swift
                amountSection
                merchantSection
                noteSection
                categorySection
                dateSection
                deleteSection
```

and add the section definition after `merchantSection` (after line 108):

```swift
    private var noteSection: some View {
        Section("Note") {
            TextField("Note (optional)", text: $note)
        }
    }
```

- [ ] **Step 4: Pass the note from `save()`**

In `EditExpenseView.swift`, replace `save()` (`:156-161`) to trim the note (empty→nil) and pass it in the new closure position:

```swift
    private func save() {
        guard let amount = parsedAmount else { return }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(amount, trimmedMerchant.isEmpty ? nil : trimmedMerchant,
               trimmedNote.isEmpty ? nil : trimmedNote, category, date)
        dismiss()
    }
```

- [ ] **Step 5: Pass the note through the Recent view's `onSave`**

In `RecentExpensesView.swift`, replace the `onSave` closure in the edit sheet (`:82-84`):

```swift
                    onSave: { amt, m, n, c, d in
                        Task { await model.update(snap, amount: amt, merchant: m, note: n, categoryName: c, date: d) }
                    },
```

- [ ] **Step 6: Build to verify it compiles (incl. macOS/CI surface)**

Run: `swift build`
Expected: build succeeds (the `onSave` arity change is consistent across `EditExpenseView` and `RecentExpensesView`).

- [ ] **Step 7: Commit**

```bash
git add Sources/GoldengoFeatures/Recent/EditExpenseView.swift Sources/GoldengoFeatures/Recent/RecentExpensesView.swift
git commit -m "feat(gol-71): edit an optional note in EditExpenseView"
```

---

## Task 5: Recent row + undo toast lead with the note

**Files:**
- Modify: `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift:346` (row), `:163` (toast)

No unit test (the precedence is already covered by `ExpenseSnapshotTests` in Task 2; this task only swaps the inline expressions for `displayTitle`).

- [ ] **Step 1: Use `displayTitle` for the row's primary text**

In `RecentExpensesView.swift`, replace line 346:

```swift
                    Text(r.displayTitle)
```

- [ ] **Step 2: Use `displayTitle` in the undo toast**

In `RecentExpensesView.swift`, replace line 163:

```swift
            "\(snapshot.displayTitle) deleted",
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoFeatures/Recent/RecentExpensesView.swift
git commit -m "feat(gol-71): Recent row + undo toast lead with the note"
```

---

## Task 6: `QuickAddModel` carries a typed note

**Files:**
- Modify: `Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift:16` (property), `:68-82` (save), `:84-88` (reset)
- Test: `Tests/GoldengoFeaturesTests/QuickAddModelTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/GoldengoFeaturesTests/QuickAddModelTests.swift` (inside the class, before the closing brace):

```swift
    func test_save_persistsTypedNote_andResetClearsIt() async throws {
        // A note typed on the Quick Add screen must reach the saved expense, and must clear after a
        // save so it never bleeds into the next entry.
        let m = try makeModel()
        m.tap("2"); m.tap("5"); m.tap("0")
        m.note = "lunch with Ana"
        await m.save()
        let rows = try await m.store.recentExpenses()
        XCTAssertEqual(rows.first?.note, "lunch with Ana")
        XCTAssertEqual(m.note, "")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter QuickAddModelTests`
Expected: FAIL — compile error (`QuickAddModel` has no `note` property).

- [ ] **Step 3: Add the `note` property**

In `QuickAddModel.swift`, add after `merchant` (line 16):

```swift
    public var merchant: String = ""
    public var note: String = ""
```

- [ ] **Step 4: Pass the note on save**

In `QuickAddModel.swift`, replace the `logManual` call in `save()` (`:71-73`):

```swift
            try await store.logManual(amount: amountDecimal, currency: currency,
                                      merchant: merchant.isEmpty ? nil : merchant,
                                      note: note.isEmpty ? nil : note,
                                      categoryName: selectedCategory)
```

- [ ] **Step 5: Clear the note on reset**

In `QuickAddModel.swift`, replace `reset()` (`:84-88`):

```swift
    public func reset() {
        amountString = ""
        merchant = ""
        note = ""
        selectedCategory = nil
    }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `swift test --filter QuickAddModelTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift Tests/GoldengoFeaturesTests/QuickAddModelTests.swift
git commit -m "feat(gol-70): QuickAddModel carries a typed note"
```

---

## Task 7: Note row on the Quick Add keypad screen

**Files:**
- Modify: `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift`

No unit test (SwiftUI view + keyboard behavior — verified by build + simulator + device). **Use the `frontend-design` skill during this task** to refine the visual treatment (glyph, spacing, emphasis) while preserving the placement and keyboard contract below. The baseline below is complete and shippable on its own.

- [ ] **Step 1: Add a focus state**

In `QuickAddView.swift`, add after the existing `@State` properties (after line 12):

```swift
    @State private var showCurrencyPicker = false
    @FocusState private var noteFocused: Bool
```

- [ ] **Step 2: Add the note field view**

In `QuickAddView.swift`, add this computed view (e.g. directly after `amountDisplay`, after line 92). `submitLabel`/`focused` are cross-platform; `textInputAutocapitalization` is iOS-only and guarded:

```swift
    private var noteField: some View {
        HStack(spacing: GoldengoTheme.Spacing.s) {
            Image(systemName: "square.and.pencil")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Add a note (optional)", text: $model.note)
                .font(.subheadline)
                .focused($noteFocused)
                .submitLabel(.done)
                .onSubmit { noteFocused = false }
#if canImport(UIKit)
                .textInputAutocapitalization(.sentences)
#endif
        }
        .padding(.horizontal, GoldengoTheme.Spacing.m)
        .padding(.vertical, 12)
        .background(Color.goldengoField)
        .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))
    }
```

- [ ] **Step 3: Place the note row between the amount and the category chips**

In `QuickAddView.swift`, update the body `VStack` (`:21-27`):

```swift
        VStack(spacing: GoldengoTheme.Spacing.l) {
            amountDisplay
            noteField
            categoryChips
            Spacer(minLength: 0)
            keypad
            addButton
        }
```

- [ ] **Step 4: Add an iOS-only keyboard "Done" toolbar as a backup dismissal**

In `QuickAddView.swift`, attach to the body `VStack` (immediately after the `.padding`/`.background` modifiers on it, before `.sheet`). `.toolbar(placement: .keyboard)` is iOS-only, so guard it:

```swift
#if canImport(UIKit)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { noteFocused = false }
            }
        }
#endif
```

- [ ] **Step 5: Build for macOS (CI surface) and the iOS simulator**

Run: `swift build`
Expected: succeeds (confirms the `#if canImport(UIKit)` guards compile on the macOS/CI build).

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run in the simulator and verify behavior**

Boot the sim, launch with seeded data, and confirm via screenshot + logs:

```bash
SIMCTL_CHILD_GOLDENGO_SEED_SAMPLE=1 xcrun simctl launch booted com.goldengo.app
xcrun simctl io booted screenshot /tmp/quickadd-note.png
xcrun simctl spawn booted log show --last 30s --info --debug --predicate 'process == "Goldengo"'
```

Expected: the note row renders under the amount; the screenshot shows the clean keypad screen with the note placeholder; **no** AttributeGraph cycles / "modifying state during view update" / hangs in the log. (Tapping the field / typing / keyboard dismissal is a device-only gesture — covered in Task 8.)

- [ ] **Step 7: Commit**

```bash
git add Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift
git commit -m "feat(gol-70): optional note row on the Quick Add keypad screen"
```

---

## Task 8: Full verification, review, and handoff

No code unless verification surfaces a defect (if so, fix TDD-style and re-run).

- [ ] **Step 1: Full test suite green**

Run: `swift test`
Expected: all tests pass — the prior baseline (185) plus the new note/displayTitle tests, zero skipped. If any fail, fix before proceeding (Rule 12 — no silent skips).

- [ ] **Step 2: App build (simulator)**

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Runtime evidence in the simulator**

With seeded data: add an expense carrying a note via the Quick Add row; confirm (screenshot) the Recent row shows the note as its primary text and the category beneath. Open an existing expense in Edit and confirm the Note field is present and editable. Capture os_log (`--info --debug`) and confirm no AttributeGraph cycles / "modifying state" / hangs while focusing and dismissing the note field.

- [ ] **Step 4: Second-Opus code review**

Dispatch a fresh general-purpose reviewer (model: opus) over the full branch diff vs `main`; triage findings, fix the real ones (TDD where logic), re-run `swift test`.

- [ ] **Step 5: Device install for the user's tap-test**

```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath AppProject/.build-device build
xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E AppProject/.build-device/Build/Products/Debug-iphoneos/Goldengo.app
```

Ask the user to confirm on-device: typing a note on Quick Add, the keyboard rising over the keypad and Return/Done returning to the keypad + Add button (the Add button reachable), the note appearing in the Recent row, and editing/clearing the note in Edit.

- [ ] **Step 6: Merge + tickets**

On the user's go: `git checkout main && git merge --ff-only feature/gol-70-71-expense-details && git push`. Set GOL-70 and GOL-71 to **To Verify** in YouTrack with a summary comment; note that epic GOL-64 is complete.

---

## Self-review

**Spec coverage** (against `2026-06-03-gol70-71-expense-details-design.md`):
- §1 ExpenseSnapshot.note + makeSnapshot → Task 1. ✓
- §2 logManual note → Task 1. ✓
- §3 updateExpense note → Task 3. ✓
- §4 displayTitle → Task 2 (used by Task 5). ✓
- §5 QuickAddModel.note → Task 6. ✓
- §6 Quick Add note row + keyboard → Task 7. ✓
- §7 EditExpenseView note + RecentExpensesModel.update → Tasks 3 (model) + 4 (view). ✓
- §8 Recent row + undo toast → Task 5. ✓
- Tests (round-trip, blank→nil, set/clear, displayTitle precedence, Quick Add reaches save) → Tasks 1, 3, 2, 6. ✓
- Out of scope (no widget / migration / project.rb) → honored; no such tasks. ✓

**Placeholder scan:** none — every code step shows complete code; every run step has an exact command + expected result.

**Type consistency:** `note` ordered after `merchant`/`merchantName` everywhere — `logManual(...merchant:note:categoryName:)`, `updateExpense(...merchant:note:categoryName:date:)` (protocol no default; concrete `= nil`), `RecentExpensesModel.update(...merchant:note:categoryName:date:)`, `EditExpenseView.onSave(amount,merchant,note,category,date)`, `RecentExpensesView` closure `{ amt, m, n, c, d }`. `ExpenseSnapshot` adds `note` after `merchantName` (declaration order) so `makeSnapshot` and the `ExpenseSnapshotTests` memberwise init both pass `...merchantName, note, kind...`. `displayTitle` = `note ?? merchantName ?? categoryName ?? "Expense"` referenced consistently in Task 2 (defined), Task 5 (row + toast). `FailingReader` fake updated to match the protocol. Consistent.
