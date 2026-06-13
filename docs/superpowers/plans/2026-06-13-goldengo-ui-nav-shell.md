# Goldengo UI Rewrite — Phase 2: Navigation Shell — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 4-tab bar (Add/Home/Subscriptions/Sources) with the locked 3-destination shell — **Home · center gold Add · Wallet** — presenting Add and Subscriptions as sheets, while preserving every existing routing path (deep links, widget/Siri `pendingTab`, share-import, rituals, re-entry) and keeping subscription reminder-sync alive.

**Architecture:** `RootView` keeps `selectedTab` for the two real tabs (Home=1, Wallet=5) and gains `showAdd`/`showSubscriptions` sheet state. A pure `RootRoute` enum + `route(forTab:)` mapping is the unit-tested seam translating a legacy tab index (used by deep links/`pendingTab`) into "select a tab" vs "present a sheet". `QuickAddView` is presented **unchanged** in the Add sheet; `SubscriptionsView` **unchanged** in the Subscriptions sheet. A new `AddFAB` design-system component is overlaid on the native 2-tab bar.

**Tech Stack:** SwiftUI, modules `GoldengoFeatures` (RootView) + `GoldengoDesignSystem` (AddFAB), XCTest via `swift test`.

**Spec:** `docs/superpowers/specs/2026-06-13-goldengo-ui-rewrite-design.md` §4. Builds on Phase 1 foundation (already merged into branch). Implements §4.1/§4.2/§4.3 + the deferred `AddFAB` (spec §3.2).

**Branch:** `ui-rewrite-quiet-luxe`.

---

## Locked decisions for this phase

- **Add is a sheet** (`showAdd`) presenting `QuickAddView` unmodified. `quickAddModel.loadSources()` runs in the sheet's `.task` (replacing the old `onChange(selectedTab==0)`); `recentModel.load()` runs in the sheet's `onDismiss` so a logged expense appears on Home. Dismissal is swipe-down (no QuickAddView surgery — its reskin/grabber is Phase 4).
- **3rd tab is the existing `SourcesView`, relabeled "Wallet"** (icon `wallet`). The Sources↔Wallet *consolidation* is deferred to Phase 5; Phase 2 only relabels.
- **Subscriptions is a sheet** (`showSubscriptions`) from Home's "Upcoming" affordance (`onOpenSubscriptions`). `subsModel.load()` runs on present.
- **Routing seam:** add `RootRoute` enum + pure `route(forTab:)`; `route(toTab:)` becomes a thin applier. `tab(forDeepLink:)` is **unchanged** (so its existing tests stay green): `quickadd`→0→Add sheet, `subscriptions`→4→Home+subs sheet.
- **Reminder sync:** `subsModel.load()` (which calls `syncReminders()`) now fires on the cold-launch `.task`, when the subs sheet opens, and after import (existing). This replaces the old tab-4-entry trigger so dropping the tab can't silently stop reminders.

---

## File structure

- **Create** `Sources/GoldengoDesignSystem/AddFAB.swift` — the center gold Add button (presentation-only).
- **Modify** `Sources/GoldengoFeatures/RootView.swift` — add `RootRoute`/`route(forTab:)`, restructure `body` (2 tabs + FAB overlay + Add/Subscriptions sheets), rewire `route(toTab:)`, callbacks, `onChange`, cold `.task`.
- **Modify** `Tests/GoldengoFeaturesTests/RootViewRoutingTests.swift` — add `route(forTab:)` mapping tests (existing `tab(forDeepLink:)`/`isStatementFile` tests untouched).

---

## Prerequisite

- [ ] **Confirm baseline green**

Run: `cd /Users/jurgenleka/Public/WorkRepos/personal-work/goldengo && swift test`
Expected: PASS (383 tests). Confirm branch `ui-rewrite-quiet-luxe`.

---

## Task 1: `AddFAB` design-system component

**Files:**
- Create: `Sources/GoldengoDesignSystem/AddFAB.swift`

Presentation-only (no branching logic) → build-gated, no unit test (Rule 9: don't write tests that can't fail).

- [ ] **Step 1: Create the component**

```swift
import SwiftUI

/// The center action of the tab bar: a prominent gold circle that opens the Add sheet.
/// Presentation-only — the navigation decision lives in `RootView`.
public struct AddFAB: View {
    private let action: () -> Void
    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(GoldengoTheme.onAccent)
                .frame(width: 60, height: 60)
                .background(GoldengoTheme.accent)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add expense")
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build complete, no errors. (If Swift 6 strict concurrency complains, the closure is `@escaping` and the view is `@MainActor` — it should be fine; if not, report.)

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoDesignSystem/AddFAB.swift
git commit -m "feat(ui-nav): AddFAB — center gold add action"
```

---

## Task 2: `RootRoute` enum + pure `route(forTab:)` mapping (tested seam)

**Files:**
- Modify: `Sources/GoldengoFeatures/RootView.swift`
- Test: `Tests/GoldengoFeaturesTests/RootViewRoutingTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to the test class in `Tests/GoldengoFeaturesTests/RootViewRoutingTests.swift`:

```swift
    func test_routeForTab_mapsTabsAndSheets() {
        XCTAssertEqual(RootView.route(forTab: 0), .add)              // quickadd → Add sheet
        XCTAssertEqual(RootView.route(forTab: 1), .tab(1))           // Home tab
        XCTAssertEqual(RootView.route(forTab: 2), .settings)         // Settings sheet
        XCTAssertEqual(RootView.route(forTab: 3), .statementImport)  // Import sheet
        XCTAssertEqual(RootView.route(forTab: 4), .subscriptions)    // Subscriptions sheet (was a tab)
        XCTAssertEqual(RootView.route(forTab: 5), .tab(5))           // Wallet tab
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter RootViewRoutingTests`
Expected: FAIL — `RootRoute` and `route(forTab:)` undefined.

- [ ] **Step 3: Add the enum + pure mapping**

In `Sources/GoldengoFeatures/RootView.swift`, add the enum at file scope (after the `RitualSheet` struct, before `public struct RootView`):

```swift
/// Where a legacy tab index resolves under the 3-destination shell. Deep links, widget taps and
/// Siri `pendingTab` still speak in the old integer indices; this maps them to "select a tab" vs
/// "present a sheet". Pure + `Equatable` so routing can't silently regress.
public enum RootRoute: Equatable, Sendable {
    case tab(Int)          // a real bottom-bar tab: Home (1) or Wallet (5)
    case add               // present the Add sheet
    case settings          // present the Settings sheet
    case statementImport   // present the Import sheet
    case subscriptions     // go to Home and present the Subscriptions sheet
}
```

Then add the pure mapping inside `RootView` (next to `tab(forDeepLink:)`):

```swift
    /// Maps a legacy tab index to a `RootRoute`. Extracted (like `tab(forDeepLink:)`) so the
    /// IA can't silently regress. 0→Add sheet, 1→Home, 2→Settings, 3→Import, 4→Subscriptions, 5→Wallet.
    public nonisolated static func route(forTab tab: Int) -> RootRoute {
        switch tab {
        case 0: return .add
        case 2: return .settings
        case 3: return .statementImport
        case 4: return .subscriptions
        default: return .tab(tab)   // 1 = Home, 5 = Wallet
        }
    }
```

(Do NOT change `route(toTab:)` yet — Task 3 wires it. This task only adds the tested pure function.)

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter RootViewRoutingTests`
Expected: PASS (existing `tab(forDeepLink:)`/`isStatementFile` tests + the new mapping test).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/RootView.swift Tests/GoldengoFeaturesTests/RootViewRoutingTests.swift
git commit -m "feat(ui-nav): RootRoute + route(forTab:) tested routing seam"
```

---

## Task 3: Restructure `RootView` body — 2 tabs + Add FAB + Add/Subscriptions sheets

**Files:**
- Modify: `Sources/GoldengoFeatures/RootView.swift`

This is the integration task. Exact replacements below; everything not listed (the helper funcs `applyPendingTab`/`checkReEntry`/`checkRitual`, the settings/import/importFile/reEntry/ritual sheet modifiers, `onChange(scenePhase)`, `onOpenURL`, the static `isStatementFile`/`tab(forDeepLink:)`/`route(forTab:)`) stays **byte-identical**.

- [ ] **Step 1: Add the two sheet-state vars**

In the `@State` block, after `@State private var showImport = false`, add:

```swift
    @State private var showAdd = false            // center FAB → Add sheet (QuickAdd)
    @State private var showSubscriptions = false  // Home "Upcoming" → Subscriptions management sheet
```

- [ ] **Step 2: Rewire `route(toTab:)` to use `RootRoute`**

Replace the entire existing `route(toTab:)` method:

```swift
    /// Settings (2) and Import (3) live behind the Home toolbar as sheets rather than permanent
    /// tabs, so deep links / widget / Siri targeting them open the matching sheet instead of a tab.
    private func route(toTab tab: Int) {
        switch tab {
        case 2: showSettings = true
        case 3: showImport = true
        default: selectedTab = tab
        }
    }
```

with:

```swift
    /// Applies a legacy tab index (from deep links / widget / Siri `pendingTab`) under the
    /// 3-destination shell: real tabs select, the rest present their sheet. See `route(forTab:)`.
    private func route(toTab tab: Int) {
        switch Self.route(forTab: tab) {
        case .tab(let t):       selectedTab = t
        case .add:              showAdd = true
        case .settings:         showSettings = true
        case .statementImport:  showImport = true
        case .subscriptions:    selectedTab = 1; showSubscriptions = true
        }
    }
```

- [ ] **Step 3: Replace the `TabView` (top of `body`) with the 2-tab + FAB overlay**

Replace this current opening of `body` — from `TabView(selection: $selectedTab) {` through its closing `}` and the `.tint(GoldengoTheme.accent)` line (i.e. lines that render QuickAdd tag 0, Home tag 1, Subscriptions tag 4, Sources tag 5):

```swift
        TabView(selection: $selectedTab) {
            QuickAddView(model: quickAddModel)
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(0)
            RecentExpensesView(
                model: recentModel,
                onAdd: { selectedTab = 0 },
                onOpenImport: { showImport = true },
                onOpenSettings: { showSettings = true },
                onOpenSubscriptions: { selectedTab = 4 },
                onChangeCurrency: { code in
                    SharedSummary().setPreferredCurrency(code)
                    quickAddModel.currency = code
                    recentModel.currency = code
                    Task { await recentModel.load() }
                }
            )
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(1)
            SubscriptionsView(model: subsModel)
                .tabItem { Label("Subscriptions", systemImage: "arrow.triangle.2.circlepath") }
                .tag(4)
            SourcesView(model: sourcesModel)
                .tabItem { Label("Sources", systemImage: "circle.grid.2x2") }
                .tag(5)
        }
        .tint(GoldengoTheme.accent)
```

with:

```swift
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                RecentExpensesView(
                    model: recentModel,
                    onAdd: { showAdd = true },
                    onOpenImport: { showImport = true },
                    onOpenSettings: { showSettings = true },
                    onOpenSubscriptions: { showSubscriptions = true },
                    onChangeCurrency: { code in
                        SharedSummary().setPreferredCurrency(code)
                        quickAddModel.currency = code
                        recentModel.currency = code
                        Task { await recentModel.load() }
                    }
                )
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(1)
                SourcesView(model: sourcesModel)
                    .tabItem { Label("Wallet", systemImage: "wallet") }
                    .tag(5)
            }
            .tint(GoldengoTheme.accent)

            // The center action straddling the bar. Sits between the two native tab items.
            // NOTE: the exact vertical placement is visual — tune `.padding(.bottom)` on simulator.
            AddFAB { showAdd = true }
                .padding(.bottom, GoldengoTheme.Spacing.xs)
        }
```

- [ ] **Step 4: Add the Add + Subscriptions sheets**

Immediately after the `ZStack { ... }` (before the existing `.sheet(isPresented: $showSettings ...)` modifier), insert:

```swift
        .sheet(isPresented: $showAdd, onDismiss: {
            // A logged expense should appear on Home without a manual refresh.
            Task { await recentModel.load() }
        }) {
            QuickAddView(model: quickAddModel)
                .task { await quickAddModel.loadSources() }   // fresh "Paid from" balances (was onChange tab 0, GOL-90)
        }
        .sheet(isPresented: $showSubscriptions, onDismiss: {
            // Confirming/dismissing a subscription can change Home's "Upcoming" section.
            Task { await recentModel.load() }
        }) {
            SubscriptionsView(model: subsModel)
                .task { await subsModel.load() }   // load on present; also re-syncs reminders (was tab 4 entry)
        }
```

- [ ] **Step 5: Update the cold-launch `.task` (re-sync reminders) and `onChange(selectedTab)`**

In the `.task { ... }` block, after `await recentModel.load()` and before `try? await store.refreshSharedSummaries()`, add:

```swift
            await subsModel.load()    // re-sync subscription reminders on cold launch (was tab-4 entry; GOL-?? reminder safety)
```

Replace the `onChange(of: selectedTab)` body:

```swift
        .onChange(of: selectedTab) { _, newTab in
            // Reload the destination tab's data on entry so adds/imports show without a manual refresh.
            if newTab == 0 { Task { await quickAddModel.loadSources() } }   // fresh "Paid from" balances (GOL-90)
            if newTab == 1 { Task { await recentModel.load() } }
            if newTab == 4 { Task { await subsModel.load() } }
            if newTab == 5 { Task { await sourcesModel.load() } }
        }
```

with (Add & Subscriptions are sheets now — their loads run on the sheet `.task`):

```swift
        .onChange(of: selectedTab) { _, newTab in
            // Reload the destination tab's data on entry so adds/imports show without a manual refresh.
            if newTab == 1 { Task { await recentModel.load() } }
            if newTab == 5 { Task { await sourcesModel.load() } }
        }
```

- [ ] **Step 6: Build, then run the full suite**

Run: `swift build` → expect Build complete.
Run: `swift test` → expect PASS (383 + the new routing test = 384). Confirm `RootViewRoutingTests` all pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/GoldengoFeatures/RootView.swift
git commit -m "feat(ui-nav): 3-destination shell — Home/Wallet tabs + center Add FAB, Add & Subscriptions as sheets"
```

---

## Task 4: Verification + behavior-preservation audit + final review

**Files:** none (verification only)

- [ ] **Step 1: Full suite**

Run: `swift test`
Expected: 384 tests, 0 failures.

- [ ] **Step 2: Static behavior-preservation audit**

Confirm by reading `RootView.swift` that ALL of these still hold (grep + eyeball):
- `onOpenURL`: `wallet` host still does `sourcesModel.pendingWalletAdjust = true; route(toTab: 5)` (Wallet tab); statement files still set `importFile`; other deep links still go through `route(toTab:)`.
- `applyPendingTab()` still calls `route(toTab:)` — so widget/Siri `pendingTab == 0` now opens the Add sheet, `== 4` opens Subscriptions, `== 2/3` open Settings/Import.
- `checkReEntry`/`checkRitual` and the reEntry `.fullScreenCover` + ritual `.sheet(item:)` are unchanged.
- Settings/Import `onDismiss` currency-refresh logic is unchanged.

Run: `grep -n "pendingWalletAdjust\|applyPendingTab\|route(toTab\|fullScreenCover\|ritualSheet" Sources/GoldengoFeatures/RootView.swift`

- [ ] **Step 3: Final review subagent**

Dispatch a code reviewer over `git diff <Phase-2-base>..HEAD -- Sources Tests` (Phase-2 base = the commit before Task 1). Focus: did the IA change preserve every routing path; is the FAB overlay sound; did reminder-sync ownership actually move; any Swift 6 concurrency issue; is `QuickAddView`/`SubscriptionsView` genuinely unmodified.

- [ ] **Step 4: Note the one manual-tuning item**

The `AddFAB` vertical placement (`.padding(.bottom, …)`) and tap-area over the native tab bar can only be confirmed visually in the simulator. Flag this to the user as the single thing to eyeball when they next build — it does not block the logic/tests.

---

## Self-review (done while writing)

- **Spec coverage (§4):** 3-tab shell (T3), center Add FAB (T1+T3), Add-as-sheet with `loadSources` preserved (T3 step 4), Subscriptions-as-sheet (T3 step 4), routing redirects via `RootRoute` (T2+T3 step 2), reminder-sync re-trigger (T3 step 5), Wallet relabel (T3 step 3). Sources↔Wallet consolidation explicitly deferred to Phase 5.
- **Placeholder scan:** none; every code step is exact; the one genuinely visual item (FAB padding) is called out, not hidden.
- **Behavior preservation:** `tab(forDeepLink:)` mapping unchanged (existing tests stay green); `pendingTab`/`onOpenURL`/rituals/re-entry paths all still flow through `route(toTab:)`/unchanged modifiers; `QuickAddView`/`SubscriptionsView`/`SourcesView` not modified.
- **Type consistency:** `RootRoute` cases (`tab/add/settings/statementImport/subscriptions`) are used identically in the enum, `route(forTab:)`, the tests, and `route(toTab:)`. `showAdd`/`showSubscriptions` named consistently.

## Definition of done

- `swift test` green (384 tests incl. new `route(forTab:)` mapping test).
- `RootView` renders Home + Wallet tabs with a center gold `AddFAB`; Add and Subscriptions present as sheets; every deep-link/widget/ritual/re-entry path preserved; subscription reminders re-sync on cold launch + subs-sheet open + import.
- `QuickAddView`, `SubscriptionsView`, `SourcesView` unchanged.
- One known visual-tuning item (FAB placement) flagged for the user.
