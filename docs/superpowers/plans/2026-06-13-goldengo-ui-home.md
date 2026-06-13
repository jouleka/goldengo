# Goldengo UI Rewrite — Phase 3: Home Recomposition — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recompose the Home screen (`RecentExpensesView`) into the Quiet-luxe layout — a serif wordmark, an "In your pocket" balance hero (read-only, with a fog caption), a calm secondary month/today row, and serif section voice — while every existing behavior (swipe-delete + undo, ghosts, Due, edit, currency menu, refresh, error state) is preserved.

**Architecture:** Add a read-only `pocket: [PocketLine]` to `HomeData` (populated by the existing `pocketSnapshot(now:)` inside `homeData(...)`), surface it on `RecentExpensesModel`, and render the hero from a pure line-selector + caption helper (both unit-tested). Extend `GoldengoAmountText` with an optional `color` so income/transfer keep their semantic tints through the one renderer. The big view recomposition is build-gated; the new logic is TDD'd.

**Tech Stack:** SwiftUI; modules `GoldengoData` (HomeData), `GoldengoFeatures` (RecentExpensesModel/View), `GoldengoDesignSystem` (GoldengoAmountText); XCTest via `swift test`.

**Spec:** `docs/superpowers/specs/2026-06-13-goldengo-ui-rewrite-design.md` §5 (Home) + decisions D3, D5, D9, D10. Builds on Phases 1–2 (foundation + nav shell, already on branch).

**Branch:** `ui-rewrite-quiet-luxe`.

---

## Grounding facts (verified)

- `HomeData` — `Sources/GoldengoData/IngestionStore+HomeData.swift:6-22`, public struct `Sendable`, explicit init over `rows, todayTotal, summary, ghosts, sources, pending`. Built inside `homeData(in:rates:now:topCategoryLimit:)`.
- `RecentExpensesModel` — `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift:6-42`, `@MainActor @Observable`; `load()` calls `reader.homeData(...)` and fans into published props (`rows`, `todayTotalText`, `summary`, `loadFailed`, `ghosts`, `pendingCharges`, `fundingSources`). Already has `loadFailed`.
- Pocket read path (read-only): `pocketSnapshot(now:) throws -> [PocketLine]` (`IngestionStore+Pocket.swift:18-61`). `PocketLine { currencyCode: String; expected: Decimal; confidence: PocketFog.Confidence; typicalCashDay: Decimal; lastMovement: Date }` (`IngestionStore+Pocket.swift:5-12`). `PocketFog` (`GoldengoCore/PocketFog.swift:6-37`) provides `silentDays(from:to:)` and `confidence(silentDays:typicalCashDay:walletTotal:) -> Confidence{ .even, .fogged(width:), .lost }`.
- `RecentExpensesView` — `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift` (507 LOC). Header is `monthCard` (lines 233-312) with an inline currency `Menu` (239-265), month total (266-270), Add button (279-287), Today total (291-298). Section labels via `GoldengoSectionLabel`: "This month" (237), "Due" (55), "Today's usuals" (61), "Recent" (66). Rows via `expenseRow(_:)` (434-492): income `.green` (487), transfer `.secondary` (480-482), expense default (489-490). `body` composes cards through `.goldengoCardRow()`.

---

## File structure

- **Modify** `Sources/GoldengoData/IngestionStore+HomeData.swift` — add `pocket` to `HomeData` (defaulted init param) + populate it in `homeData(...)`.
- **Modify** `Sources/GoldengoDesignSystem/GoldengoAmountText.swift` — optional `color` param.
- **Modify** `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift` — `pocketLines` prop, pure `heroPocketLine(from:currency:)` + `pocketCaption(for:now:)`, computed `pocketHeroText`/`pocketCaptionText`/`hasWallet`.
- **Modify** `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift` — recompose header into `homeHeader` (wordmark + pocket hero + secondary month/today), extract `currencyMenuControl`, swap section labels to `GoldengoSerifSectionHeader`, route row amounts through `GoldengoAmountText`.
- **Modify** `Tests/GoldengoFeaturesTests/` — new `HomePocketTests.swift` for the pure selector + caption.

---

## Prerequisite

- [ ] **Baseline green:** `swift test` → 384 pass. Confirm branch `ui-rewrite-quiet-luxe`.

---

## Task 1: Read-only pocket data on `HomeData`

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore+HomeData.swift`

- [ ] **Step 1: Add `pocket` to `HomeData` (additive, defaulted)**

In the `HomeData` struct, add a stored property after `pending`:
```swift
    /// Read-only per-currency wallet snapshot for the Home "In your pocket" hero (GOL UI rewrite).
    /// Rides the home fetch; Home never writes wallet state.
    public let pocket: [PocketLine]
```
And add a **defaulted** param to the end of `init` so existing constructors/tests compile unchanged:
```swift
    public init(rows: [ExpenseSnapshot], todayTotal: Decimal, summary: DashboardSummary,
                ghosts: [RhythmGhost], sources: [FundingSourceOption], pending: [PendingSubscriptionCharge],
                pocket: [PocketLine] = []) {
        self.rows = rows; self.todayTotal = todayTotal; self.summary = summary
        self.ghosts = ghosts; self.sources = sources; self.pending = pending
        self.pocket = pocket
    }
```

- [ ] **Step 2: Populate it in `homeData(...)`**

Find where `homeData(in:rates:now:topCategoryLimit:)` constructs and returns `HomeData(...)` in this file. Add the pocket read just before the return, and pass it. The snapshot is best-effort (a wallet read must never fail the whole Home load):
```swift
        let pocket = (try? pocketSnapshot(now: now)) ?? []
```
and add `pocket: pocket` to the `HomeData(...)` initializer call.

- [ ] **Step 3: Build + full suite**

Run: `swift build` then `swift test` → expect 384 pass (additive change; no test asserts the new field yet).

- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoData/IngestionStore+HomeData.swift
git commit -m "feat(ui-home): read-only pocket snapshot on HomeData (defaulted, non-breaking)"
```

---

## Task 2: `GoldengoAmountText` optional color (reconciles D5 + D9)

**Files:**
- Modify: `Sources/GoldengoDesignSystem/GoldengoAmountText.swift`

- [ ] **Step 1: Add an optional `color` param (default = inkPrimary)**

Change the stored props + init + body. Replace the current `private let text`/`private let role` + `init` + `body` so it reads:
```swift
    private let text: String
    private let role: Role
    private let color: Color?

    public init(_ text: String, role: Role = .row, color: Color? = nil) {
        self.text = text
        self.role = role
        self.color = color
    }
```
and in `body`, change `.foregroundStyle(GoldengoTheme.inkPrimary)` to:
```swift
            .foregroundStyle(color ?? GoldengoTheme.inkPrimary)
```
(Leave `pointSize(for:)`/`tracking(for:)` and their tests untouched.)

- [ ] **Step 2: Build + design-system tests**

Run: `swift build` then `swift test --filter GoldengoDesignSystemTests` → expect PASS (the sizing/tracking tests are unaffected; `color` is presentation, build-gated).

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoDesignSystem/GoldengoAmountText.swift
git commit -m "feat(ui-home): GoldengoAmountText optional color (income/transfer keep semantic tint)"
```

---

## Task 3: Pocket hero logic on `RecentExpensesModel` (TDD)

**Files:**
- Modify: `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift`
- Test: `Tests/GoldengoFeaturesTests/HomePocketTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoFeaturesTests/HomePocketTests.swift`:
```swift
import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

final class HomePocketTests: XCTestCase {
    private func line(_ code: String, expected: Decimal, typical: Decimal, daysAgo: Int) -> PocketLine {
        let when = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: .now)!
        return PocketLine(currencyCode: code, expected: expected, confidence: .even,
                          typicalCashDay: typical, lastMovement: when)
    }

    func test_heroPocketLine_prefersSelectedCurrencyThenFirst() {
        let lines = [line("ALL", expected: 8000, typical: 0, daysAgo: 0),
                     line("EUR", expected: 120, typical: 0, daysAgo: 0)]
        XCTAssertEqual(RecentExpensesModel.heroPocketLine(from: lines, currency: .init("EUR"))?.currencyCode, "EUR")
        // No match (or .all) → first line (balances are sorted ALL-first upstream).
        XCTAssertEqual(RecentExpensesModel.heroPocketLine(from: lines, currency: .all)?.currencyCode, "ALL")
        XCTAssertNil(RecentExpensesModel.heroPocketLine(from: [], currency: .all))
    }

    func test_pocketCaption_threeStates() {
        // Even: recent movement, never fogs.
        XCTAssertEqual(RecentExpensesModel.pocketCaption(for: line("EUR", expected: 100, typical: 0, daysAgo: 0), now: .now),
                       "ready to spend")
        // Fogged: silent days * typical < wallet → losing track.
        let fogged = line("EUR", expected: 100, typical: 5, daysAgo: 4)   // 20 < 100
        XCTAssertEqual(RecentExpensesModel.pocketCaption(for: fogged, now: .now),
                       "losing track — reconcile when your wallet's out")
        // Lost: drift exceeds the wallet.
        let lost = line("EUR", expected: 100, typical: 40, daysAgo: 4)    // 160 >= 100
        XCTAssertEqual(RecentExpensesModel.pocketCaption(for: lost, now: .now),
                       "lost track — reconcile when your wallet's out")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter HomePocketTests`
Expected: FAIL — `pocketLines`/`heroPocketLine`/`pocketCaption` undefined.

- [ ] **Step 3: Implement on the model**

In `RecentExpensesModel`, ensure `import GoldengoCore` is present (for `PocketFog`). Add the published property alongside the others:
```swift
    /// Read-only per-currency wallet snapshot driving the "In your pocket" hero. Home never writes wallet.
    public private(set) var pocketLines: [PocketLine] = []
```
In `load()`, after `fundingSources = data.sources`, add:
```swift
        pocketLines = data.pocket
```
Add the pure helpers + computed view-facing strings (place after `load()`):
```swift
    /// The wallet line the hero shows: the one matching the display currency, else the first
    /// (balances arrive ALL-first), else nil when there is no wallet.
    public static func heroPocketLine(from lines: [PocketLine], currency: CurrencyCode) -> PocketLine? {
        if let match = lines.first(where: { $0.currencyCode == currency.rawValue }) { return match }
        return lines.first
    }

    /// In-app fog caption (the lock-screen widget keeps its own phrasing). Always paired with the
    /// REAL figure shown in the hero (D10) — the caption conveys uncertainty, it never hides the number.
    public static func pocketCaption(for line: PocketLine?, now: Date) -> String {
        guard let line else { return "" }
        let silent = PocketFog.silentDays(from: line.lastMovement, to: now)
        switch PocketFog.confidence(silentDays: silent, typicalCashDay: line.typicalCashDay, walletTotal: line.expected) {
        case .even:   return "ready to spend"
        case .fogged: return "losing track — reconcile when your wallet's out"
        case .lost:   return "lost track — reconcile when your wallet's out"
        }
    }

    public var hasWallet: Bool { !pocketLines.isEmpty }

    /// The hero's money string (real figure, formatted in the line's own currency), or "" if no wallet.
    public var pocketHeroText: String {
        guard let line = Self.heroPocketLine(from: pocketLines, currency: currency) else { return "" }
        return Money(amount: line.expected, currency: CurrencyCode(line.currencyCode)).formatted()
    }

    public var pocketCaptionText: String {
        Self.pocketCaption(for: Self.heroPocketLine(from: pocketLines, currency: currency), now: .now)
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter HomePocketTests` → PASS. Then `swift test` → 386 pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift Tests/GoldengoFeaturesTests/HomePocketTests.swift
git commit -m "feat(ui-home): pocket hero selector + fog caption on RecentExpensesModel (TDD)"
```

---

## Task 4: Recompose the Home header — wordmark + pocket hero + secondary totals

**Files:**
- Modify: `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`

- [ ] **Step 1: Extract the currency menu**

The currency `Menu` is currently inline inside `monthCard` (lines ~239-265). Extract it verbatim into a computed property so the new header can place it next to the hero:
```swift
    private var currencyMenuControl: some View {
        Menu {
            ForEach(menuCurrencies, id: \.rawValue) { c in
                Button { onChangeCurrency(c) } label: {
                    if c.rawValue == model.currency.rawValue {
                        Label(menuLabel(c), systemImage: "checkmark")
                    } else {
                        Text(menuLabel(c))
                    }
                }
            }
            Divider()
            Button { showCurrencyPicker = true } label: {
                Label("More currencies…", systemImage: "ellipsis.circle")
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(model.currency.symbol).font(.system(size: 26, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .foregroundStyle(GoldengoTheme.accent)
            .contentShape(Rectangle())
        }
    }
```

- [ ] **Step 2: Replace `monthCard` with `homeHeader`**

Replace the entire `private var monthCard: some View { ... }` (lines ~233-312) with `homeHeader` below. It leads with the wordmark + Add, then the pocket hero, then a quiet month/today row. (The `.sheet(isPresented: $showCurrencyPicker)` that was attached at the end of `monthCard` MUST be preserved — keep it attached to `homeHeader`.)
```swift
    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("Goldengo").font(.system(.title3, design: .serif)).foregroundStyle(GoldengoTheme.accent)
                Spacer()
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, GoldengoTheme.Spacing.m)
                        .padding(.vertical, GoldengoTheme.Spacing.s)
                        .background(GoldengoTheme.accent)
                        .foregroundStyle(GoldengoTheme.onAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Pocket hero (real figure always; caption conveys fog — D10).
            VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.xs) {
                GoldengoSectionLabel("In your pocket")
                if model.hasWallet {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        currencyMenuControl
                        GoldengoAmountText(model.pocketHeroText, role: .hero)
                    }
                    Text(model.pocketCaptionText).font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                } else {
                    Text("Set your wallet to begin").font(.subheadline).foregroundStyle(GoldengoTheme.inkMuted)
                }
            }

            Divider()

            // Secondary: month + today, calm.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: GoldengoTheme.Spacing.xs) {
                    GoldengoSerifSectionHeader("This month")
                    GoldengoAmountText(model.monthAmountText(), role: .title)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: GoldengoTheme.Spacing.xs) {
                    Text("Today").font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                    GoldengoAmountText(model.todayTotalText, role: .row)
                }
            }
            if let asOf = model.ratesAsOf {
                Text("Rates as of \(asOf.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption2).foregroundStyle(GoldengoTheme.inkMuted)
            }
        }
        .goldengoCard(padding: GoldengoTheme.Spacing.l)
        .sheet(isPresented: $showCurrencyPicker) {
            CurrencyPickerView(selectedCode: Binding(
                get: { model.currency.rawValue },
                set: { onChangeCurrency(CurrencyCode($0)) }
            ))
        }
    }
```
NOTE: if the existing `monthCard`'s `showCurrencyPicker` sheet body differs from the `CurrencyPickerView(...)` call above, use the EXISTING body verbatim — do not change the picker wiring, only move it onto `homeHeader`. Read lines ~299-311 and copy the real sheet closure.

- [ ] **Step 3: Point `body` at `homeHeader`**

In `body`, change the header row from `monthCard.goldengoCardRow()` to `homeHeader.goldengoCardRow()`.

- [ ] **Step 4: Build + full suite**

Run: `swift build` then `swift test` → 386 pass. (Logic unchanged; this is presentation.)

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/Recent/RecentExpensesView.swift
git commit -m "feat(ui-home): pocket-hero header — serif wordmark, in-your-pocket hero, calm month/today"
```

---

## Task 5: Serif section voice + amounts through `GoldengoAmountText`

**Files:**
- Modify: `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`

- [ ] **Step 1: Section headers → serif (D3 — keep `GoldengoSectionLabel` type intact, just stop using it for these)**

Replace the section labels in `body` and `categoriesCard`:
- `GoldengoSectionLabel("Due")` → `GoldengoSerifSectionHeader("Upcoming")` (the Due section becomes the serif "Upcoming" voice).
- `GoldengoSectionLabel("Today's usuals")` → `GoldengoSerifSectionHeader("Today's usuals")`.
- `GoldengoSectionLabel("Recent")` → `GoldengoSerifSectionHeader("Recent")`.
- In `categoriesCard(_:)`, the `GoldengoSectionLabel("...")` title → `GoldengoSerifSectionHeader("...")` (keep the same title string).
- Leave the "In your pocket" eyebrow in the hero as `GoldengoSectionLabel` (that uppercase micro-label IS the right voice for an eyebrow).

- [ ] **Step 2: Row amounts → `GoldengoAmountText` (D5) keeping semantic tints (D9)**

In `expenseRow(_:)`, replace the three amount branches (lines ~478-490) with `GoldengoAmountText`, preserving income green / transfer muted via the new `color` param:
```swift
            if r.kind == .transfer {
                GoldengoAmountText(Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted(),
                                   role: .row, color: GoldengoTheme.inkMuted)
            } else if r.kind == .income {
                GoldengoAmountText("+" + Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted(),
                                   role: .row, color: .green)
            } else {
                GoldengoAmountText(Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted(),
                                   role: .row)
            }
```

- [ ] **Step 3: Build + full suite**

Run: `swift build` then `swift test` → 386 pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoFeatures/Recent/RecentExpensesView.swift
git commit -m "feat(ui-home): serif section voice + amounts through GoldengoAmountText (income/transfer tints kept)"
```

---

## Task 6: Verification + behavior audit + final review

**Files:** none (verification only)

- [ ] **Step 1: Full suite** — `swift test` → 386 pass, 0 failures.
- [ ] **Step 2: Behavior-preservation audit** — read `RecentExpensesView.swift` and confirm intact: swipe-to-delete + undo toast (`deleteWithUndo`/`undoToast`/`recentlyDeleted`), `.refreshable` → `model.load()`, `EditExpenseView` `.sheet(item: $editing)`, ghost/pending tap → `GoldengoHaptics.spendLanded()` + `model.confirm`/`logPending`, the "Adjust amount" alert/contextMenu, the `loadFailed` error banner, the `ContentUnavailableView` empty state, and `onOpenSubscriptions`/`onOpenImport`/`onOpenSettings` callbacks. Run: `grep -nE "deleteWithUndo|undoToast|refreshable|sheet\(item: \\\$editing|spendLanded|loadFailed|ContentUnavailableView|onOpenSubscriptions" Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`
- [ ] **Step 3: Final review subagent** over `git diff <Phase-3-base>..HEAD`. Focus: pocket read path is genuinely read-only (Home never writes wallet); hero currency selection + caption correct; income/transfer tints preserved; no behavior lost in the header swap; the `showCurrencyPicker` sheet wiring is intact; Swift 6 clean.
- [ ] **Step 4: Flag visual-tuning items** for the user's simulator pass (hero size on small devices / long ALL values; serif header rhythm).

---

## Self-review (done while writing)

- **Spec coverage (§5 Home):** pocket hero w/ read-only path (T1+T3+T4), fog caption real-figure D10 (T3+T4), serif voice D3 (T4+T5), one amount renderer + semantic tints D5/D9 (T2+T5), currency menu preserved (T4), Upcoming label (T5). Subscriptions management already opens as a sheet (Phase 2 `onOpenSubscriptions`).
- **Decisions surfaced:** hero shows one currency line (no FX sum); in-app caption phrasing is simpler than the widget's (in-app context) — both noted in code comments.
- **Placeholders:** none; the one "copy the real sheet closure" instruction (T4 step 2) is because the exact `showCurrencyPicker` body must be taken verbatim from the file rather than guessed — explicitly called out, not hand-waved.
- **Type consistency:** `pocketLines`/`heroPocketLine`/`pocketCaption`/`pocketHeroText`/`pocketCaptionText`/`hasWallet` used identically across model, tests, and view; `GoldengoAmountText(_, role:, color:)` signature consistent.

## Definition of done

- `swift test` green (386: +2 HomePocketTests).
- Home shows the serif wordmark + "In your pocket" hero (real figure + fog caption) + calm month/today; serif section voice; amounts via `GoldengoAmountText` with income green / transfers muted preserved.
- Pocket path is read-only; every existing Home behavior preserved.
- Known visual-tuning items flagged for the simulator pass.
