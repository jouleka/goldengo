# Add-flow Completeness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backdating (QuickAdd + AddIncome), a collapsed "Add details" (where/note) row, and user-creatable categories with a most-recently-used chip row.

**Architecture:** One new read API (`recentCategoryNames` — MRU order derived from recent expenses, no schema change); `QuickAddModel` gains a `date` property and a merged `quickCategories`; the sheets gain a "When" DatePicker row, an expandable details row, and a ＋New category chip reusing the AddIncome new-source field pattern. Spec: `docs/superpowers/specs/2026-07-02-addflow-completeness-design.md`.

**Tech Stack:** Swift / SwiftData / SwiftUI, XCTest via `swift test`.

## Global Constraints

- Date pickers bounded `...Date.now` — future entries corrupt wallet expected balance and today totals.
- Never compare `Decimal` in `#Predicate`; bounded fetches only.
- Full `swift test` green before each commit.

---

### Task 1: `recentCategoryNames` store API

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift` (near `expenseCount`)
- Test: `Tests/GoldengoDataTests/ReadMethodsTests.swift` (append)

**Interfaces:**
- Produces: `IngestionStore.recentCategoryNames(limit: Int = 200) throws -> [String]`

- [ ] **Step 1: Failing test** (append to `ReadMethodsTests`)

```swift
    func test_recentCategoryNames_mostRecentFirst_distinct_skipsArchived() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.logManual(amount: 5, currency: .all, merchant: "a", categoryName: "Coffee", date: base)
        _ = try await store.logManual(amount: 5, currency: .all, merchant: "b", categoryName: "Books", date: base.addingTimeInterval(60))
        _ = try await store.logManual(amount: 5, currency: .all, merchant: "c", categoryName: "Coffee", date: base.addingTimeInterval(120))
        let gone = try await store.logManual(amount: 5, currency: .all, merchant: "d", categoryName: "Vice", date: base.addingTimeInterval(180))
        try await store.deleteExpense(dedupeKey: gone)
        let names = try await store.recentCategoryNames()
        // WHY: the chip row is a habit surface — most-recently-USED first, one chip per
        // category, and deleted history must not resurrect chips.
        XCTAssertEqual(names, ["Coffee", "Books"])
    }
```

- [ ] **Step 2: Run** — `swift test --filter ReadMethodsTests` → compile error (no member `recentCategoryNames`). If `deleteExpense(dedupeKey:)` differs, use the actual archival API found in `RecentExpensesModel`.

- [ ] **Step 3: Implement** (in `IngestionStore.swift`)

```swift
    /// Distinct category names of the most recent expenses, most-recently-used first —
    /// the QuickAdd chip row's habit surface. Derived from recent rows (one bounded fetch,
    /// date desc), so it needs no usage counters and deleted history drops out naturally.
    public func recentCategoryNames(limit: Int = 200) throws -> [String] {
        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = limit
        var seen = Set<String>()
        var names: [String] = []
        for r in try modelContext.fetch(fd) {
            guard let name = r.category?.name, !name.isEmpty, seen.insert(name.lowercased()).inserted
            else { continue }
            names.append(name)
        }
        return names
    }
```

- [ ] **Step 4: Run** — PASS. **Step 5: Commit** `feat(data): recentCategoryNames — MRU distinct category names`

---

### Task 2: `QuickAddModel` date + merged categories

**Files:**
- Modify: `Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift`
- Test: `Tests/GoldengoFeaturesTests/QuickAddModelTests.swift` (append)

**Interfaces:**
- Consumes: `recentCategoryNames` (Task 1).
- Produces: `QuickAddModel.date: Date`, `QuickAddModel.loadCategories() async`,
  `QuickAddModel.mergeCategories(recent:defaults:) -> [String]` (static, pure),
  `quickCategories` now `private(set) var`.

- [ ] **Step 1: Failing tests**

```swift
    func test_mergeCategories_userFirst_dedupedCaseInsensitive_capped10() {
        let merged = QuickAddModel.mergeCategories(
            recent: ["Vape", "coffee", "Books", "Gym", "Vet", "Gifts", "Tools", "Rent"],
            defaults: ["Groceries", "Food", "Transport", "Coffee", "Bills", "Shopping", "Other"])
        // WHY: the row must mirror the user's actual habits before our guesses, one chip
        // per category regardless of case, and stay scannable (cap 10).
        XCTAssertEqual(merged, ["Vape", "coffee", "Books", "Gym", "Vet", "Gifts", "Tools", "Rent",
                                "Groceries", "Food"])
    }

    @MainActor
    func test_save_forwardsPickedDate_thenResetsToToday() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = QuickAddModel(store: store, currency: .all)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        model.tap("5"); model.date = yesterday
        await model.save()
        let row = try await store.recentExpenses(limit: 1).first
        // WHY: backdating exists so a forgotten spend lands on the day it happened…
        XCTAssertEqual(row?.date, yesterday)
        // …and a sticky yesterday would silently mis-date every FOLLOWING log.
        XCTAssertTrue(Calendar.current.isDateInToday(model.date))
    }
```

- [ ] **Step 2: Run** — compile failure (no `mergeCategories`/`date`).

- [ ] **Step 3: Implement** — in `QuickAddModel`:
  - Add `public var date: Date = .now`.
  - Replace `public let quickCategories = [...]` with:

```swift
    /// Default chips until real usage exists; merged with most-recently-used on load.
    public static let defaultCategories = ["Groceries", "Food", "Transport", "Coffee", "Bills", "Shopping", "Other"]
    /// Most-used categories surfaced as one-tap chips — the user's own (MRU) first,
    /// topped up with the defaults, one chip per name, capped to stay scannable.
    public private(set) var quickCategories = QuickAddModel.defaultCategories

    public func loadCategories() async {
        let recent = (try? await store.recentCategoryNames()) ?? []
        quickCategories = Self.mergeCategories(recent: recent, defaults: Self.defaultCategories)
    }

    /// Pure merge: recent (MRU) first, defaults top up, case-insensitive dedupe, cap 10.
    public nonisolated static func mergeCategories(recent: [String], defaults: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in recent + defaults where seen.insert(name.lowercased()).inserted {
            out.append(name)
            if out.count == 10 { break }
        }
        return out
    }
```

  - In `save()`: pass `date: date` to `logManual`, and in the success path (with `reset()`) set `date = .now`. Also call `await loadCategories()` next to `loadSources()` so a just-created category becomes a chip immediately.

- [ ] **Step 4: Run** — `swift test --filter QuickAddModelTests` → PASS. **Step 5: Commit** `feat(quickadd): backdate-able date + MRU category chips (model)`

---

### Task 3: Sheet UI — When row, Add details, ＋New category, income date

**Files:**
- Modify: `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift`
- Modify: `Sources/GoldengoFeatures/Provenance/AddIncomeView.swift`
- Modify: `Sources/GoldengoFeatures/Provenance/SourcesModel.swift` (`addIncome` gains `date: Date = .now`, forwarded to `store.logIncome(date:)`)

**Interfaces:** Consumes Task 2's model API. No new public API beyond `addIncome(date:)`.

- [ ] **Step 1: QuickAddView**
  - After `categoryChips`, add a ＋New chip + capsule name field (AddIncome new-source pattern): `@State newCategoryMode`, `@State newCategoryText`, `@FocusState detailsFocused` shared by the three text fields; selecting sets `model.selectedCategory = newCategoryText`.
  - "Add details" quiet button (13pt, muted, `plus.circle`) toggling two capsule TextFields bound to `$model.merchant` ("Where?") and `$model.note` ("Note"); row stays expanded while either is non-empty; fields use `.submitLabel(.done)`.
  - "When" row after `paidFromRow`: `GoldengoSectionLabel("When")` + `DatePicker("", selection: $model.date, in: ...Date.now, displayedComponents: .date).labelsHidden().tint(GoldengoTheme.accent)`.
  - In `tap(_:)`: clear the text-field focus before forwarding (tap-outside rule).
  - New-category text becomes the selected category live: `.onChange(of: newCategoryText) { model.selectedCategory = $0.isEmpty ? nil : $0 }` (guarded to the newCategoryMode case).
- [ ] **Step 2: AddIncomeView** — add `@State private var date = Date.now`; a matching "When" row above the keypad; pass `date: date` into `model.addIncome`.
- [ ] **Step 3: SourcesModel.addIncome** — signature `addIncome(amount:currency:sourceName:intoWallet:date:)` with `date: Date = .now`, forwarded.
- [ ] **Step 4: Verify** — `swift build` + full `swift test` green; existing `AddIncomeViewTests`/`SourcesModelTests` still pass (default parameter keeps call sites source-compatible).
- [ ] **Step 5: Commit** `feat(addflow): When row (backdating), Add details, ＋New category chip`

---

### Task 4: Device verification

- [ ] `xcodebuild … -destination 'id=7B8F5F4F-B6B9-5A41-926D-31C29770064E' build` → BUILD SUCCEEDED; `devicectl … install` → App installed.
- [ ] User checks: backdate a coffee to yesterday; add a "Vape" category via ＋New; details row collapsed by default.
