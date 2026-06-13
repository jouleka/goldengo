# Goldengo UI Rewrite — Phase 5: Wallet / Sources / Income — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reskin the money-provenance screens into Quiet luxe — make "money moves through" visual with a gold-aware `DrainingPoolBar`, route amounts/CTAs through the shared components, give Wallet/Sources their missing error state, and add serif voice — preserving every behavior (reconcile, denomination counter, GOL-98 widget deep-link, add-income cash-vs-bank). Also clears the deferred `nonisolated` test-warning cleanup.

**Architecture:** New `DrainingPoolBar` (GeometryReader fill, clamps 0…1, no stray dot at 0) in `GoldengoDesignSystem` replaces the inline `ProgressView`. `model.loadFailed` (already set, never rendered) gets a calm error card + pull-to-refresh in both SourcesView and WalletView. AdjustWallet's Save becomes `GoldButton`; amounts become `GoldengoAmountText`; titles/section headers become serif. Logic untouched.

**Tech Stack:** SwiftUI; `GoldengoDesignSystem` (DrainingPoolBar + the nonisolated fix), `GoldengoFeatures` (Sources/Wallet/AddIncome); XCTest via `swift test`.

**Spec:** §5 (Wallet, Sources, Add income) + the completeness-critic gaps (error state, a11y on the bar) + D1/D5. Builds on Phases 1–4.

**Branch:** `ui-rewrite-quiet-luxe`.

---

## Grounding facts (verified)

- **SourcesView** (`Provenance/SourcesView.swift`, List-based): wallet entry button (33-59), source pool `ForEach(model.snapshot?.sources ?? [])` (61-75) with `ProgressView(value: model.fraction(b)).tint(model.color(b))`, "Unaccounted" row (76-84), `ContentUnavailableView` empty (87-93), "Add income" toolbar (98-102). Opens WalletView via `showCount`, AddIncomeView via `showAddIncome`. Does **not** render `model.loadFailed`. No `.refreshable` noted.
- **WalletView + AdjustWalletView** (`Provenance/WalletView.swift`): per-currency `NavigationLink` lines (45-57) with `Text("~" + Money(...).formatted())`; `AdjustWalletView` (113-235): title `Text("What's in your wallet?").font(.title2.weight(.bold))`, big input `TextField` at `.system(size: 40, weight: .bold, design: .rounded)`, `counterDisclosure` (178-202, DisclosureGroup of Steppers), `resultLine`, `saveButton` (204-233: inline `GoldengoTheme.accent` + `.black`, `disabled(busy || typedAmount == nil)`, calls `model.setWalletBalance`). GOL-98 `autoOpenAdjust`/`adjustPresented` (100-106). No error state.
- **AddIncomeView** (`Provenance/AddIncomeView.swift`, Form): `Section("Amount"/"Currency"/"From"/"Date")` + cash-in-hand `Toggle` section (75-81); amount `TextField` at `.title2.weight(.semibold)`; "From" suggestion chips (Capsule on `goldengoSurface`); `NavigationLink` → `CurrencyPickerView`; toolbar Cancel + `Button("Add"){...}.disabled(!canSave)`; `model.addIncome(..., intoWallet: cashInHand)`.
- **SourcesModel**: `loadFailed` (14), `fraction(_)->Double` clamped (51-55), `color(_)` (67-69), `remainingText(_)`/`unaccountedText()` (57-63), `setWalletBalance`/`addIncome`, `load()`.
- **No** `DrainingPoolBar` in GoldengoDesignSystem. `GoldButton`, `GoldengoAmountText`, `GoldengoSerifSectionHeader`, tokens all exist.
- Deferred from Phase 4: `GoldButton.fill/labelTint` + `GoldengoAmountText.pointSize/tracking` emit `#ActorIsolatedCall` warnings when called from tests → fix by marking `nonisolated static`.

---

## File structure

- **Modify** `Sources/GoldengoDesignSystem/GoldButton.swift`, `GoldengoAmountText.swift` — `nonisolated static` on the pure helpers.
- **Create** `Sources/GoldengoDesignSystem/DrainingPoolBar.swift`.
- **Modify** `Sources/GoldengoFeatures/Provenance/SourcesView.swift` — DrainingPoolBar, error state + refresh, serif, amounts, a11y.
- **Modify** `Sources/GoldengoFeatures/Provenance/WalletView.swift` — serif title, amounts, GoldButton Save, monospaced input, error state.
- **Modify** `Sources/GoldengoFeatures/Provenance/AddIncomeView.swift` — serif Form headers, gold tint, monospaced amount.

---

## Prerequisite

- [ ] **Baseline green:** `swift test` → 386 pass. Branch `ui-rewrite-quiet-luxe`.

---

## Task 1: Clear the deferred `nonisolated` test warnings

**Files:** Modify `Sources/GoldengoDesignSystem/GoldButton.swift`, `Sources/GoldengoDesignSystem/GoldengoAmountText.swift`

- [ ] **Step 1: Mark the pure statics `nonisolated`**

In `GoldButton.swift`, change the two static funcs:
```swift
    public static func fill(isEnabled: Bool) -> Fill { isEnabled ? .accent : .field }
    public static func labelTint(isEnabled: Bool) -> LabelTint { isEnabled ? .onAccent : .muted }
```
to `public nonisolated static func fill(...)` and `public nonisolated static func labelTint(...)` (add `nonisolated` before `static`, bodies unchanged).

In `GoldengoAmountText.swift`, change `public static func pointSize(for role: Role) -> CGFloat` and `public static func tracking(for role: Role) -> CGFloat` to `public nonisolated static func ...` (bodies unchanged).

- [ ] **Step 2: Build + tests** — `swift build` and `swift test --filter GoldengoDesignSystemTests` → 11 pass; confirm the `#ActorIsolatedCall` warnings in `FoundationTests` are gone (`swift test 2>&1 | grep -c ActorIsolatedCall` → 0).

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoDesignSystem/GoldButton.swift Sources/GoldengoDesignSystem/GoldengoAmountText.swift
git commit -m "chore(ui): nonisolated static on pure DS helpers (clears ActorIsolatedCall test warnings)"
```

---

## Task 2: `DrainingPoolBar` component

**Files:** Create `Sources/GoldengoDesignSystem/DrainingPoolBar.swift`

Presentation-only → build-gated.

- [ ] **Step 1: Create**

```swift
import SwiftUI

/// A horizontal "money draining" bar: a quiet track with a source-tinted fill sized to `fraction`
/// (remaining ÷ inflow). Clamps 0…1; at 0 the fill has zero width (no stray dot). Decorative —
/// the consuming row owns the accessibility label.
public struct DrainingPoolBar: View {
    private let fraction: Double
    private let tint: Color

    public init(fraction: Double, tint: Color) {
        self.fraction = min(max(fraction, 0), 1)
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.goldengoField)
                if fraction > 0 {
                    Capsule().fill(tint).frame(width: geo.size.width * fraction)
                }
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: Build** — `swift build` → complete. `swift test --filter GoldengoDesignSystemTests` → 11 pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoDesignSystem/DrainingPoolBar.swift
git commit -m "feat(ui-wallet): DrainingPoolBar — source-tinted draining fill (clamped, zero-safe)"
```

---

## Task 3: SourcesView reskin + error state

**Files:** Modify `Sources/GoldengoFeatures/Provenance/SourcesView.swift`

READ FIRST. Preserve: wallet entry → `showCount`, `showAddIncome`, GOL-98 `pendingWalletAdjust`/`walletAdjustTarget()`, empty state condition, toolbar Add.

- [ ] **Step 1: Source pool row → `DrainingPoolBar` + serif + amount + a11y**

Replace the source `ForEach` body (61-75) with:
```swift
            ForEach(model.snapshot?.sources ?? []) { b in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle().fill(model.color(b)).frame(width: 9, height: 9)
                        Text(b.name).font(.subheadline.weight(.semibold)).foregroundStyle(GoldengoTheme.inkPrimary)
                        Spacer()
                        GoldengoAmountText(model.remainingText(b), role: .row)
                    }
                    DrainingPoolBar(fraction: model.fraction(b), tint: model.color(b))
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(b.name), \(model.remainingText(b)) left, \(Int((model.fraction(b) * 100).rounded()))% remaining")
            }
```

- [ ] **Step 2: Error state + pull-to-refresh**

Add a calm error card as the FIRST row inside the `List` (before the wallet entry button):
```swift
                if model.loadFailed {
                    HStack(spacing: GoldengoTheme.Spacing.s) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Couldn't load your money. Pull to refresh.")
                    }
                    .font(.subheadline).foregroundStyle(GoldengoTheme.danger)
                    .listRowBackground(Color.clear)
                }
```
And ensure the `List` has `.refreshable { await model.load() }` (add it if not already present, alongside the existing list modifiers).

- [ ] **Step 3: "In your wallet" + "Unaccounted" token alignment**

In the wallet entry button, change the per-currency summary `Text(...).font(.subheadline.weight(.medium))` to add `.foregroundStyle(GoldengoTheme.inkPrimary)`, and the helper text `.foregroundStyle(.secondary)` → `.foregroundStyle(GoldengoTheme.inkMuted)`. In the "Unaccounted" row, change `.foregroundStyle(.secondary)` (both label and amount) → `.foregroundStyle(GoldengoTheme.inkMuted)`.

- [ ] **Step 4: Build + full suite** — `swift build`; `swift test` → 386 pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/Provenance/SourcesView.swift
git commit -m "feat(ui-wallet): Sources reskin — DrainingPoolBar, amounts, error state + refresh, a11y"
```

---

## Task 4: WalletView + AdjustWalletView reskin

**Files:** Modify `Sources/GoldengoFeatures/Provenance/WalletView.swift`

READ FIRST. Preserve: per-currency `NavigationLink` → AdjustWallet, GOL-98 `autoOpenAdjust`/`adjustPresented`, `label(for:)`, the denomination `counterDisclosure` + `tally` sync, `typedAmount` regex, `setWalletBalance` + `resultLine` + `dismiss` outcome logic, `GoldengoHaptics.spendLanded()`, `.onTapGesture { focused = false }`.

- [ ] **Step 1: Per-currency line amount → `GoldengoAmountText`**

In the `ForEach(model.wallet)` line label, change:
```swift
              Text("~" + Money(amount: line.expectedNow,
                               currency: CurrencyCode(line.currencyCode)).formatted())
                  .font(.subheadline.weight(.medium))
```
to:
```swift
              GoldengoAmountText("~" + Money(amount: line.expectedNow,
                                             currency: CurrencyCode(line.currencyCode)).formatted(),
                                 role: .row)
```
And the currency label `Text(label(for: line.currencyCode)).font(.subheadline.weight(.semibold))` → add `.foregroundStyle(GoldengoTheme.inkPrimary)`.

- [ ] **Step 2: AdjustWallet serif title + monospaced input**

In `AdjustWalletView.body`, change `Text("What's in your wallet?").font(.title2.weight(.bold))` → `.font(.system(.title2, design: .serif)).foregroundStyle(GoldengoTheme.inkPrimary)`. Change the "books expect" caption `.foregroundStyle(.secondary)` → `.foregroundStyle(GoldengoTheme.inkMuted)`. Change the input `TextField`'s `.font(.system(size: 40, weight: .bold, design: .rounded))` → `.font(.system(size: 40, weight: .semibold).monospacedDigit())`. Change the `resultLine` `.foregroundStyle(.secondary)` → `.foregroundStyle(GoldengoTheme.inkMuted)`.

- [ ] **Step 3: Save → `GoldButton`**

Replace the entire `saveButton` computed var with one that wraps the SAME action in `GoldButton` (copy the existing action body verbatim into the closure):
```swift
    private var saveButton: some View {
        GoldButton("Save", isEnabled: !busy && typedAmount != nil) {
            guard !busy, let total = typedAmount else { return }
            busy = true
            focused = false
            GoldengoHaptics.spendLanded()
            Task {
                let tallyToSave = (showCounter && tally.total == total) ? tally : nil
                let outcome = await model.setWalletBalance(total, currency: currency, tally: tallyToSave)
                if outcome == nil {
                    resultLine = "Couldn't save — try again."
                    busy = false
                } else if let gap = outcome?.unaccountedLogged {
                    resultLine = Money(amount: gap, currency: currency).formatted()
                        + " logged as Unaccounted — delete it in Recent if that's wrong."
                    busy = false
                } else {
                    dismiss()
                }
            }
        }
    }
```
(Verify this matches the current action body exactly when you read the file; if the comments/strings differ, keep the file's real strings.)

- [ ] **Step 4: WalletView error state**

In `WalletView.body`'s `List`, add a calm error row when `model.loadFailed` (mirror Task 3 step 2, same styling), and ensure `.refreshable { await model.load() }` is present on the list.

- [ ] **Step 5: Build + full suite** — `swift build`; `swift test` → 386 pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoFeatures/Provenance/WalletView.swift
git commit -m "feat(ui-wallet): Wallet + AdjustWallet reskin — serif title, GoldButton save, monospaced input, error state"
```

---

## Task 5: AddIncomeView reskin

**Files:** Modify `Sources/GoldengoFeatures/Provenance/AddIncomeView.swift`

READ FIRST. Preserve: `cashInHand` toggle semantics + descriptions, `canSave`, `model.addIncome(..., intoWallet: cashInHand)`, the `CurrencyPickerView` NavigationLink, suggestion-chip tap-to-fill, Cancel/Add toolbar, `.onTapGesture { amountFocused = false }`.

- [ ] **Step 1: Serif section headers**

Convert each `Section("X") { <body> }` (Amount, Currency, From, Date) to the `header:`-closure form keeping the body verbatim:
```swift
            Section { <body> } header: { GoldengoSerifSectionHeader("X") }
```
(The cash-in-hand toggle `Section { Toggle ... }` has no string title — leave its structure, just ensure its description text uses `GoldengoTheme.inkMuted` instead of `.secondary`.)

- [ ] **Step 2: Amount + tints + gold**

Add `.monospacedDigit()` to the amount `TextField` font (`.font(.title2.weight(.semibold))` → `.font(.title2.weight(.semibold).monospacedDigit())`). Add `.tint(GoldengoTheme.accent)` to the `Form` (gold Add/DatePicker). Change the suggestion-chip background `Color.goldengoSurface` → `Color.goldengoField` and add `.foregroundStyle(GoldengoTheme.inkPrimary)` to the chip text (token alignment; they stay tap-to-fill, NOT SelectableChip since they aren't a selected state).

- [ ] **Step 3: Build + full suite** — `swift build`; `swift test` → 386 pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoFeatures/Provenance/AddIncomeView.swift
git commit -m "feat(ui-wallet): Add income reskin — serif Form headers, gold tint, monospaced amount"
```

---

## Task 6: Verification + behavior audit + final review

**Files:** none

- [ ] **Step 1: Full suite** — `swift test` → 386 pass, 0 failures. `swift test 2>&1 | grep -c ActorIsolatedCall` → 0.
- [ ] **Step 2: Behavior audit** — `grep -nE "setWalletBalance|addIncome|pendingWalletAdjust|autoOpenAdjust|adjustPresented|spendLanded|cashInHand|typedAmount|counterDisclosure|showCount|showAddIncome|loadFailed|refreshable" Sources/GoldengoFeatures/Provenance/*.swift` — confirm reconcile, denomination counter, GOL-98 deep-link, cash-vs-bank, and the new error/refresh are all present.
- [ ] **Step 3: Final review subagent** over `git diff <Phase-5-base>..HEAD`. Focus: DrainingPoolBar zero/full clamp + a11y on the row (not the bar); error state renders `loadFailed` and refresh retries; GoldButton Save preserves the exact outcome/dismiss logic; GOL-98 auto-open intact; income cash-vs-bank intact; Swift 6 clean + no ActorIsolatedCall.
- [ ] **Step 4: Flag visual-tuning items** — DrainingPoolBar height/rhythm; AdjustWallet 40pt input on small screens.

## Self-review (done while writing)

- **Spec coverage (§5):** DrainingPoolBar (T2, used T3), Sources amounts/serif/error (T3), Wallet serif/amounts/GoldButton/error (T4), Add income serif/gold/monospaced (T5). Error-state gap (completeness critic) closed in both Sources + Wallet (T3/T4). a11y on pool rows (T3). Deferred nonisolated cleanup (T1).
- **Placeholders:** none; exact replacements given. The Save-button copy instruction (T4 step 3) explicitly says verify-against-file because the action body must match verbatim.
- **Type consistency:** `DrainingPoolBar(fraction:tint:)`, `GoldButton(_, isEnabled:, action:)`, `GoldengoAmountText(_, role:)`, `GoldengoSerifSectionHeader(_)` consistent with Phases 1–4.

## Definition of done

- `swift test` green (386), zero `#ActorIsolatedCall` warnings.
- Sources shows DrainingPoolBars + amounts + serif + an error state with pull-to-refresh; Wallet/AdjustWallet reskinned with GoldButton save + monospaced input + error state; Add income has serif headers + gold + monospaced amount.
- Reconcile, denomination counter, GOL-98 deep-link, and cash-vs-bank income all preserved.
- Visual-tuning items flagged.
