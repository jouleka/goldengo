# Goldengo UI Rewrite — Phase 4: Add + Receipt — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reskin the two input surfaces — Quick Add (the center-FAB sheet) and Receipt review — into Quiet luxe: the deferred shared `SelectableChip` (D4), the amount through `GoldengoAmountText`, the primary CTA through `GoldButton`, serif voice — with every behavior (save, toast, haptic, scanner, currency/paid-from menus, keypad, OCR fields) preserved.

**Architecture:** Build `SelectableChip` once in `GoldengoDesignSystem` and use it in both screens (replacing two identical inline chip blocks). Route QuickAdd's typed amount through `GoldengoAmountText(.hero)` (the currency menu already shows the symbol separately, so the symbol-stripped amount string is correct). Swap QuickAdd's inline Add button for `GoldButton`. Reskin Receipt's `Form` with serif section headers + gold tint. Logic untouched; presentation only (build-gated), except `SelectableChip`'s selected-state mapping isn't worth a unit test (pure presentation).

**Tech Stack:** SwiftUI; `GoldengoDesignSystem` (SelectableChip), `GoldengoFeatures` (QuickAddView, ReceiptReviewView); XCTest via `swift test`.

**Spec:** `docs/superpowers/specs/2026-06-13-goldengo-ui-rewrite-design.md` §5 (Add, Receipt) + D4 (selected chip = gold-soft + gold hairline + gold label), D5 (amount renderer), D1 (GoldButton/onAccent). Builds on Phases 1–3.

**Branch:** `ui-rewrite-quiet-luxe`.

---

## Grounding facts (verified)

- **QuickAddView** (`Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift`): amount display `amountDisplay` (lines ~103-118) is `Text(...)` at `.system(size: 64, weight: .bold, design: .rounded)` + `.contentTransition(.numericText())`, with a "New expense" `.subheadline`/`.secondary` label above and `currencyMenu` beside it (the menu shows `model.currency.symbol`; the amount string carries no symbol). Category chips `categoryChips` (197-218): inline `ForEach(model.quickCategories)` → `Button`→`Label`, selected = `GoldengoTheme.accent` fill + `.black`, else `goldengoSurface` + `.primary`, `Capsule()`. Add button `addButton` (314-328): `accent`/`.black` when `model.canSave`, else `goldengoField`/`.secondary`; action `noteFocused = false; Task { await model.save() }`. Toast + `GoldengoHaptics.spendLanded()` fire on `model.savedCount` change (90-98). Keypad (285-310) = `goldengoField` tiles at `Radius.control`. Paid-from row (224-277) = a `Menu` pill on `goldengoField`. Scanner is iOS-only.
- **ReceiptReviewView** (`Sources/GoldengoFeatures/Receipt/ReceiptReviewView.swift`): `NavigationStack { Form { ... } }` with `Section("Amount"/"Merchant"/"Date"/"Category")`. Amount section: `Text(symbol)` + `TextField` at `.title2.weight(.semibold)` + unreadable hint. Category chips (47-67): identical inline pattern (`.padding(.vertical, 8)`). Toolbar `.confirmationAction` "Save" (`disabled(!model.canSave)`, fires `spendLanded()` then `Task { await model.save(); onDone() }`); `.cancellationAction` "Cancel" → `onDone()`.
- **No** existing `SelectableChip`/`ChipButton` in `GoldengoDesignSystem`. `GoldButton`, `GoldengoAmountText(_, role:, color:)`, `GoldengoSerifSectionHeader`, `GoldengoTheme.accentSoft/onAccent/inkPrimary/inkMuted` all exist (Phases 1-3).

---

## File structure

- **Create** `Sources/GoldengoDesignSystem/SelectableChip.swift` — the shared selectable pill (D4).
- **Modify** `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift` — amount→`GoldengoAmountText`, serif title, chips→`SelectableChip`, Add→`GoldButton`.
- **Modify** `Sources/GoldengoFeatures/Receipt/ReceiptReviewView.swift` — serif section headers, chips→`SelectableChip`, gold tint, monospaced amount.

---

## Prerequisite

- [ ] **Baseline green:** `swift test` → 386 pass. Branch `ui-rewrite-quiet-luxe`.

---

## Task 1: `SelectableChip` shared component (D4)

**Files:**
- Create: `Sources/GoldengoDesignSystem/SelectableChip.swift`

Presentation-only → build-gated (no unit test).

- [ ] **Step 1: Create the component**

```swift
import SwiftUI

/// A selectable pill (category / paid-from). Selected = gold-soft wash + 1px gold hairline + gold
/// label (gold used sparingly, never a solid fill behind the chip — D4); unselected = quiet field
/// fill + ink label. Shared by Add and Receipt (and later Edit).
public struct SelectableChip: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? GoldengoTheme.accent : GoldengoTheme.inkPrimary)
            .background(isSelected ? GoldengoTheme.accentSoft : Color.goldengoField)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(isSelected ? GoldengoTheme.accent : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build** — `swift build` → Build complete. `swift test --filter GoldengoDesignSystemTests` → 11 pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoDesignSystem/SelectableChip.swift
git commit -m "feat(ui-add): SelectableChip — shared gold-soft selected pill (D4)"
```

---

## Task 2: QuickAddView reskin

**Files:**
- Modify: `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift`

READ THE FILE FIRST. Preserve all behavior (save, toast/haptic via `savedCount`, scanner, currency menu, paid-from menu, keypad `tap`, note field focus/dismiss).

- [ ] **Step 1: Amount display + serif title**

In `amountDisplay`, replace the "New expense" label and the big `Text(...)` amount. Change:
```swift
        Text("New expense")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
```
to:
```swift
        Text("New expense")
            .font(.system(.title3, design: .serif))
            .foregroundStyle(GoldengoTheme.inkMuted)
```
and change:
```swift
            Text(model.amountString.isEmpty ? "0" : model.amountString)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(model.amountString.isEmpty ? Color.secondary : Color.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: model.amountString)
```
to:
```swift
            GoldengoAmountText(model.amountString.isEmpty ? "0" : model.amountString,
                               role: .hero,
                               color: model.amountString.isEmpty ? GoldengoTheme.inkMuted : nil)
                .animation(.snappy, value: model.amountString)
```
(`GoldengoAmountText` already applies `.monospacedDigit()` + `.contentTransition(.numericText())`. The hero is ~44pt vs the old 64pt — more headroom for long values; flag for the simulator pass.)

- [ ] **Step 2: Category chips → `SelectableChip`**

Replace the inner `ForEach` body in `categoryChips` (the `Button { ... } label: { Label(...) ... }` block) with:
```swift
            ForEach(model.quickCategories, id: \.self) { cat in
                SelectableChip(cat, systemImage: GoldengoCategoryIcon.symbol(for: cat),
                               isSelected: model.selectedCategory == cat) {
                    model.selectedCategory = (model.selectedCategory == cat) ? nil : cat
                }
            }
```
(Keep the surrounding `ScrollView(.horizontal)`+`HStack(spacing: .s)` exactly.)

- [ ] **Step 3: "Paid from" label → token**

In `paidFromRow`, change `Text("Paid from").font(.subheadline).foregroundStyle(.secondary)` to use the design eyebrow:
```swift
            GoldengoSectionLabel("Paid from")
```
(This is the one screen the spec keeps `GoldengoSectionLabel` for — D3.)

- [ ] **Step 4: Add button → `GoldButton`**

Replace the entire `addButton` computed var body with:
```swift
    private var addButton: some View {
        GoldButton("Add expense", isEnabled: model.canSave) {
            noteFocused = false
            Task { await model.save() }
        }
    }
```

- [ ] **Step 5: Build + full suite** — `swift build` → complete. `swift test` → 386 pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift
git commit -m "feat(ui-add): QuickAdd reskin — serif title, GoldengoAmountText hero, SelectableChip, GoldButton"
```

---

## Task 3: ReceiptReviewView reskin

**Files:**
- Modify: `Sources/GoldengoFeatures/Receipt/ReceiptReviewView.swift`

READ THE FILE FIRST. Preserve the save/cancel/onDone/`canSave`/haptic flow and the `amountWasUnreadable` hint.

- [ ] **Step 1: Serif section headers**

Convert the four sections from `Section("Title") { ... }` to a `header:`-closure form with a serif header. For each (`"Amount"`, `"Merchant"`, `"Date"`, `"Category"`), change `Section("X") {` … `}` to:
```swift
            Section {
                // ... existing section body unchanged ...
            } header: {
                GoldengoSerifSectionHeader("X")
            }
```
(Keep each section's body exactly; only the wrapper/header changes.)

- [ ] **Step 2: Amount field + hint tokens**

In the Amount section, add `.monospacedDigit()` to the `TextField`'s font: change `.font(.title2.weight(.semibold))` to `.font(.title2.weight(.semibold)).monospacedDigit()`. Change the unreadable hint `.foregroundStyle(.secondary)` to `.foregroundStyle(GoldengoTheme.inkMuted)`. Change the leading `Text(model.currency.symbol).foregroundStyle(.secondary)` to `.foregroundStyle(GoldengoTheme.inkMuted)`.

- [ ] **Step 3: Category chips → `SelectableChip`**

Replace the inner `ForEach` body in the Category section's chip block with:
```swift
                        ForEach(categories, id: \.self) { cat in
                            SelectableChip(cat, systemImage: GoldengoCategoryIcon.symbol(for: cat),
                                           isSelected: model.selectedCategory == cat) {
                                model.selectedCategory = (model.selectedCategory == cat) ? nil : cat
                            }
                        }
```
(Keep the `ScrollView(.horizontal)`+`HStack`.)

- [ ] **Step 4: Gold Save tint**

Add `.tint(GoldengoTheme.accent)` to the `Form` (so the "Save" confirmation action and the DatePicker read gold). Place it next to the existing `.scrollContentBackground(.hidden)` / `.background(...)` modifiers on the `Form`.

- [ ] **Step 5: Build + full suite** — `swift build` → complete. `swift test` → 386 pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoFeatures/Receipt/ReceiptReviewView.swift
git commit -m "feat(ui-add): Receipt review reskin — serif headers, SelectableChip, gold Save, monospaced amount"
```

---

## Task 4: Verification + behavior audit + final review

**Files:** none (verification only)

- [ ] **Step 1: Full suite** — `swift test` → 386 pass, 0 failures.
- [ ] **Step 2: Behavior audit** — confirm intact in QuickAddView: `model.save()`, `savedCount`→toast+`spendLanded`, currency menu + picker sheet, paid-from menu, keypad `tap`/`backspace`, note focus dismiss, scanner `fullScreenCover` + `scanModel` sheet, the "Couldn't save" alert. In ReceiptReviewView: Cancel/Save toolbar, `canSave` gating, `spendLanded`, `onDone`, `amountWasUnreadable` hint. Run: `grep -nE "savedCount|spendLanded|loadSources|showScanner|scanModel|model.save|canSave|amountWasUnreadable|backspace|tap\(" Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift Sources/GoldengoFeatures/Receipt/ReceiptReviewView.swift`
- [ ] **Step 3: Final review subagent** over `git diff <Phase-4-base>..HEAD`. Focus: SelectableChip correctly used in both (no leftover inline chips); amount/CTA route through the shared components; income/other behavior unchanged; the symbol on the QuickAdd amount is NOT doubled (amount string is symbol-less, the currency menu owns the symbol — confirm); Swift 6 clean.
- [ ] **Step 4: Flag visual-tuning items** — QuickAdd hero at 44pt for long values; chip wrap on small screens; serif Form header rhythm.

---

## Self-review (done while writing)

- **Spec coverage (§5 Add/Receipt):** SelectableChip D4 (T1, used T2+T3), amount via GoldengoAmountText D5 (T2), GoldButton D1 (T2), serif voice (T2 title, T3 headers), gold Save (T3). Paid-from keeps GoldengoSectionLabel (D3, T2 step 3). Scanner/numpad behavior untouched.
- **No-doubled-symbol check:** QuickAdd's amount string carries no currency symbol (the `currencyMenu` shows it separately) — verified in the map — so `GoldengoAmountText(amountString)` beside `currencyMenu` is correct (unlike the Home-hero bug, which used `.formatted()`). Receipt's amount has the symbol as a separate leading `Text` already.
- **Placeholders:** none; exact old→new strings or precise section targets given. The Receipt `Section("X")`→`header:` conversion is described structurally because there are four near-identical sections — the implementer applies the same transform to each, keeping each body verbatim.
- **Type consistency:** `SelectableChip(_ title:, systemImage:, isSelected:, action:)` used identically in both views; `GoldButton`/`GoldengoAmountText` signatures match Phases 1/3.

## Definition of done

- `swift test` green (386).
- Add and Receipt both use `SelectableChip`; QuickAdd amount via `GoldengoAmountText`, CTA via `GoldButton`, serif title; Receipt has serif section headers + gold Save + monospaced amount.
- Every save/scan/toast/haptic/menu behavior preserved; QuickAdd amount symbol not doubled.
- Visual-tuning items flagged for the simulator pass.
