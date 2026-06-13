# Goldengo UI Rewrite — Phase 6: Secondary Sheets — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the eight remaining secondary sheets (Morning, Evening, PastNotes, Re-entry, Settings, Import, Currency picker, Edit expense) into Quiet luxe by applying the now-established patterns — serif voice, `GoldButton`, `SelectableChip`, `GoldengoAmountText`, tokens — plus the last deferred component `GoldGlyphBadge` (Morning/Re-entry). Behavior preserved throughout.

**Architecture:** New `GoldGlyphBadge` (72pt accent-soft circle + hairline + thin gold glyph) in `GoldengoDesignSystem`. Then per-screen reskins: replace `.black`-on-gold buttons with `GoldButton`, `.secondary` with `inkMuted`, serif titles/section headers, Edit's inline chips with `SelectableChip` (+ a matching gold-soft restyle for the paid-from chips that carry a source dot), Import's `.green` success → gold (D9) + a success haptic, Currency picker's selected-row gold-soft wash + empty-results state. All logic untouched.

**Tech Stack:** SwiftUI; `GoldengoDesignSystem` (GoldGlyphBadge), `GoldengoFeatures`; XCTest via `swift test`.

**Spec:** §5 (all secondary screens) + D1/D4/D9. Builds on Phases 1–5. `.navigationTitle`s stay system-font (established codebase convention — serif is for in-content titles/headers).

**Branch:** `ui-rewrite-quiet-luxe`.

---

## Grounding facts (verified)

- **MorningView**: `Image("sun.max.fill")` size 48 accent; title `Text("What's today about?").font(.title2.weight(.bold))`; subtitle `.secondary`; `TextField(.roundedBorder)`; Save button `background(accent).foregroundStyle(.black)`; "Skip for today" `.secondary`. `save()` → `setIntention` + `spendLanded()` + `onDone`; `.onDisappear` skip-marking. **Preserve** save/skip/onDisappear.
- **EveningView**: title `Text("Close your day").font(.title.weight(.bold))`; intention quote + ghost rows (plus-circle accent, `spendLanded` + `model.confirm`); "Past notes" button `.secondary`; Done button accent+`.black`. `.task { model.load() }`, `.onDisappear { model.markReflected() }`. Lots of `.secondary`. **Preserve** ghosts/load/markReflected/past-notes sheet.
- **PastNotesView**: title `.title2.bold`; date `.secondary`; quote `.body`. Read-only.
- **ReEntryView**: `Image("sunrise.fill")` size 56 accent; title `Text("Welcome back").font(.title.weight(.bold))`; body `.secondary`; "Here's today" button accent+`.black`. `init(daysAway:, onContinue:)`.
- **SettingsView**: Form with string `Section("Currency"/"Quick-log gesture"/"Apple Pay auto-log"/"Privacy"/"Subscriptions"/"Daily check-in")`; "Open Shortcuts"/"Open iOS Settings" buttons; Toggles/Stepper/DatePickers; caption `.secondary` (lines 58,71,88,97,111,123); `.navigationTitle("Settings")`; Done toolbar. **Preserve** all `.onChange` scheduling + `.task` auth check.
- **ImportView**: `intro` (icon `square.and.arrow.down` size 34 accent + headline + `.secondary` caption); `actionButton(prominent:)` (card rows); `resultCard` (success glyph `.green`, failure `danger`); `model.resultText`/`model.result.isFailure`; `.navigationTitle("Import")`; no haptic today. **Preserve** fileImporter, auto-import `.task`, importCSV.
- **CurrencyPickerView** (cross-platform, no `#if`): `Section("Suggested"/"All currencies")`; `row(_)` = gold symbol well + name `.primary` + code `.secondary` + selected gold checkmark; `.searchable`; flat results when querying (no empty state). **Preserve** selection→dismiss, search, suggested/others/results.
- **EditExpenseView**: Form; string `Section("Amount"/"Merchant"/"Note"/"Category"/"Paid from"/...)`; amount `TextField(.title3.weight(.medium))` + currency Menu (`.secondary`); category chips inline `selected ? accent/.black : goldengoField/.primary`; `paidFromChip(label:dot:selected:action:)` SAME inline pattern (with optional source dot); `DatePicker`; destructive Delete (alert); Save toolbar (`disabled(parsedAmount == nil)`) → `onSave`; `onDelete`. No haptics. **Preserve** onSave/onDelete/parsedAmount/currency picker sheet.
- **No** `GoldGlyphBadge` yet. `GoldButton`, `SelectableChip`, `GoldengoAmountText`, `GoldengoSerifSectionHeader`, `GoldengoTheme.{accent,accentSoft,onAccent,inkPrimary,inkMuted,hairline,danger}` all exist.

---

## File structure

- **Create** `Sources/GoldengoDesignSystem/GoldGlyphBadge.swift`.
- **Modify** `Sources/GoldengoFeatures/Ritual/{MorningView,EveningView,PastNotesView}.swift`, `Sources/GoldengoFeatures/ReEntryView.swift`.
- **Modify** `Sources/GoldengoFeatures/Settings/{SettingsView,CurrencyPickerView}.swift`, `Sources/GoldengoFeatures/Import/ImportView.swift`.
- **Modify** `Sources/GoldengoFeatures/Recent/EditExpenseView.swift`.

---

## Prerequisite

- [ ] **Baseline green:** `swift test` → 386 pass. Branch `ui-rewrite-quiet-luxe`.

---

## Task 1: `GoldGlyphBadge` component

**Files:** Create `Sources/GoldengoDesignSystem/GoldGlyphBadge.swift`

- [ ] **Step 1: Create**

```swift
import SwiftUI

/// A calm focal glyph for landing/ritual screens: a thin gold SF Symbol in a gold-soft circle with a
/// hairline ring. Decorative (accessibility-hidden — the screen's title carries the meaning).
public struct GoldGlyphBadge: View {
    private let systemName: String
    public init(_ systemName: String) { self.systemName = systemName }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(GoldengoTheme.accent)
            .frame(width: 72, height: 72)
            .background(GoldengoTheme.accentSoft)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(GoldengoTheme.hairline, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: Build** — `swift build`; `swift test --filter GoldengoDesignSystemTests` → 11 pass.
- [ ] **Step 3: Commit** — `git add Sources/GoldengoDesignSystem/GoldGlyphBadge.swift && git commit -m "feat(ui-sheets): GoldGlyphBadge — calm gold focal glyph for landing screens"`

---

## Task 2: Rituals + Re-entry (Morning, Evening, PastNotes, ReEntry)

**Files:** Modify the four files. READ EACH FIRST; preserve all behavior listed in Grounding.

- [ ] **Step 1: MorningView** — Replace the sun `Image(...)` with `GoldGlyphBadge("sun.max")`. Title → `.font(.system(.title2, design: .serif)).foregroundStyle(GoldengoTheme.inkPrimary)`. Subtitle `.secondary` → `GoldengoTheme.inkMuted`. Replace the `TextField(.roundedBorder)` styling with a field-fill: drop `.textFieldStyle(.roundedBorder)` and add `.padding(.horizontal, GoldengoTheme.Spacing.m).padding(.vertical, 12).background(Color.goldengoField).clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.control, style: .continuous))` (keep `.focused`/`.onSubmit`). Replace the Save `Button {...} label {...}.background(accent).foregroundStyle(.black)...` with `GoldButton("Save") { save() }`. "Skip for today" → `.foregroundStyle(GoldengoTheme.inkMuted)`.

- [ ] **Step 2: EveningView** — Title → serif (`.font(.system(.title, design: .serif)).foregroundStyle(GoldengoTheme.inkPrimary)`). All `.foregroundStyle(.secondary)` (intention caption, no-note text, past-notes button, ghost amount, "Today" label, "You were trying…") → `GoldengoTheme.inkMuted`. The ghost-section header `Text("Anything usual today?").font(.headline)` → `GoldengoSerifSectionHeader("Anything usual today?")`. The spend-recap amount `model.todayTotalText` → `GoldengoAmountText(model.todayTotalText, role: .row)`. Replace the Done button with `GoldButton("Done") { onDone() }`. Keep the ghost rows' `spendLanded`+`confirm` and the plus-circle accent icon.

- [ ] **Step 3: PastNotesView** — Title → `.font(.system(.title2, design: .serif)).foregroundStyle(GoldengoTheme.inkPrimary)`. Date `.secondary` → `GoldengoTheme.inkMuted`. Quote stays `.body` but add `.foregroundStyle(GoldengoTheme.inkPrimary)`.

- [ ] **Step 4: ReEntryView** — Replace the sunrise `Image(...)` with `GoldGlyphBadge("sunrise")`. Title → serif (`.font(.system(.title, design: .serif)).foregroundStyle(GoldengoTheme.inkPrimary)`). Body `.secondary` → `GoldengoTheme.inkMuted`. Replace the "Here's today" button with `GoldButton("Here's today") { onContinue() }`.

- [ ] **Step 5: Build + full suite** — `swift build`; `swift test` → 386 pass.
- [ ] **Step 6: Commit** — `git add Sources/GoldengoFeatures/Ritual/ Sources/GoldengoFeatures/ReEntryView.swift && git commit -m "feat(ui-sheets): rituals + re-entry reskin — GoldGlyphBadge, serif titles, GoldButton, tokens"`

---

## Task 3: Settings + Import + Currency picker

**Files:** Modify the three files. READ EACH FIRST.

- [ ] **Step 1: SettingsView** — Convert each string `Section("X") { <body> }` to `Section { <body> } header: { GoldengoSerifSectionHeader("X") }` (all six, bodies verbatim). All caption `.foregroundStyle(.secondary)` → `GoldengoTheme.inkMuted`. Add `.tint(GoldengoTheme.accent)` to the `Form` (gold toggles/steppers/pickers + Done). The "Open Shortcuts"/"Open iOS Settings" `Button { } label: { Label(...) }` → add `.foregroundStyle(GoldengoTheme.accent)` to each Label. Keep `.navigationTitle("Settings")` (system). Preserve ALL `.onChange`/`.task` scheduling logic.

- [ ] **Step 2: ImportView** — `intro`: replace the `Image("square.and.arrow.down")...` with `GoldGlyphBadge("square.and.arrow.down")`; the caption `.secondary` → `GoldengoTheme.inkMuted`. `resultCard`: change the success glyph color `.green` → `GoldengoTheme.accent` (failure stays `GoldengoTheme.danger`); `model.resultText` Text → add `.foregroundStyle(GoldengoTheme.inkPrimary)`. Fire a success haptic: in BOTH the "Try a sample" action and the auto-import `.task`, after the `await model.importCSV(...)` completes, add `if !model.result.isFailure { GoldengoHaptics.spendLanded() }`. `actionButton` subtitle `.secondary` → `GoldengoTheme.inkMuted`. Keep `.navigationTitle("Import")`, fileImporter, prominent/non-prominent styling.

- [ ] **Step 3: CurrencyPickerView** — Convert `Section("Suggested")`/`Section("All currencies")` to `header: { GoldengoSerifSectionHeader("…") }` form. In `row(_)`: name `.primary` → `GoldengoTheme.inkPrimary`, code `.secondary` → `GoldengoTheme.inkMuted`; add a selected-row wash by attaching `.listRowBackground(c.rawValue == selectedCode ? GoldengoTheme.accentSoft : nil)` to the row. Add an empty-results state: when `!query.isEmpty && results.isEmpty`, show (instead of the flat ForEach) a centered `VStack` with `Text("No matches").font(.system(.title3, design: .serif))` + `Text("Try a different name or 3-letter code.").font(.caption).foregroundStyle(GoldengoTheme.inkMuted)`. Keep cross-platform (no new `#if`-gated iOS-only modifiers; `.listRowBackground`/`.searchable` are fine). Preserve selection→dismiss.

- [ ] **Step 4: Build + full suite** — `swift build`; `swift test` → 386 pass.
- [ ] **Step 5: Commit** — `git add Sources/GoldengoFeatures/Settings/ Sources/GoldengoFeatures/Import/ && git commit -m "feat(ui-sheets): Settings/Import/Currency reskin — serif headers, gold tint, success haptic, empty results"`

---

## Task 4: Edit expense

**Files:** Modify `Sources/GoldengoFeatures/Recent/EditExpenseView.swift`. READ FIRST. Preserve `onSave`/`onDelete`/`parsedAmount`/`save()`/delete alert/currency picker sheet.

- [ ] **Step 1: Serif section headers** — Convert `Section("Amount"/"Merchant"/"Note"/"Category"/"Paid from")` (and any other string-titled section) to `header: { GoldengoSerifSectionHeader("X") }` form, bodies verbatim.

- [ ] **Step 2: Amount + currency menu tokens** — Amount `TextField`'s `.font(.title3.weight(.medium))` → `.font(.title3.weight(.medium).monospacedDigit())`. The currency Menu label `.foregroundStyle(.secondary)` → `GoldengoTheme.inkMuted`. Add `.tint(GoldengoTheme.accent)` to the `Form`.

- [ ] **Step 3: Category chips → `SelectableChip`** — Replace the category `ForEach(categories, id: \.self) { cat in let selected...; Button {...} label: { Label(...) ...accent/.black... } }` with:
```swift
                        ForEach(categories, id: \.self) { cat in
                            SelectableChip(cat, systemImage: GoldengoCategoryIcon.symbol(for: cat),
                                           isSelected: category == cat) {
                                category = (category == cat) ? nil : cat
                            }
                        }
```

- [ ] **Step 4: Paid-from chips → gold-soft restyle (keep the dot)** — Replace the `paidFromChip` helper body's styling to match `SelectableChip` (gold-soft selected, gold ring, ink label) while keeping the optional source-color dot:
```swift
    private func paidFromChip(label: String, dot: Color?, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(label).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, GoldengoTheme.Spacing.m)
            .padding(.vertical, 8)
            .foregroundStyle(GoldengoTheme.inkPrimary)
            .background(selected ? GoldengoTheme.accentSoft : Color.goldengoField)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(selected ? GoldengoTheme.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 5: Build + full suite** — `swift build`; `swift test` → 386 pass.
- [ ] **Step 6: Commit** — `git add Sources/GoldengoFeatures/Recent/EditExpenseView.swift && git commit -m "feat(ui-sheets): Edit expense reskin — serif headers, SelectableChip + gold-soft paid-from, monospaced amount"`

---

## Task 5: Verification + behavior audit + final review

**Files:** none

- [ ] **Step 1: Full suite** — `swift test` → 386 pass, 0 failures; `swift test 2>&1 | grep -c ActorIsolatedCall` → 0.
- [ ] **Step 2: Behavior audit** — `grep -nE "spendLanded|setIntention|markReflected|onDone|onContinue|onSave|onDelete|parsedAmount|importCSV|result.isFailure|selectedCode|dismiss\(\)|onChange" Sources/GoldengoFeatures/Ritual/*.swift Sources/GoldengoFeatures/ReEntryView.swift Sources/GoldengoFeatures/Settings/*.swift Sources/GoldengoFeatures/Import/ImportView.swift Sources/GoldengoFeatures/Recent/EditExpenseView.swift` — confirm rituals' save/skip/reflect, Settings scheduling, Import import/result, Edit save/delete, Currency selection all intact.
- [ ] **Step 3: Final review subagent** over `git diff <Phase-6-base>..HEAD`. Focus: every screen's behavior preserved (especially Settings' notification scheduling onChange and Morning's onDisappear skip-marking); GoldGlyphBadge/serif/GoldButton applied consistently; Edit chips use SelectableChip + the matching paid-from restyle; Import success = gold + haptic; Currency empty-results + selected wash; no `.black`-on-gold or stray `.secondary` left on these screens; cross-platform CurrencyPicker still compiles; Swift 6 clean.
- [ ] **Step 4: Flag visual-tuning items** for the simulator pass.

## Self-review (done while writing)

- **Spec coverage (§5):** GoldGlyphBadge (T1, used Morning/ReEntry/Import); rituals+reentry serif/GoldButton/tokens (T2); Settings serif/gold/tokens (T3); Import gold-success+haptic+badge (T3, D9); Currency serif/selected-wash/empty-state (T3); Edit SelectableChip+paid-from+serif+monospaced (T4).
- **Placeholders:** none; exact old→new per screen. Section→header conversions described structurally (repeated transform) with bodies kept verbatim.
- **Type consistency:** `GoldGlyphBadge(_)`, `GoldButton(_){}`, `SelectableChip(_, systemImage:, isSelected:, action:)`, `GoldengoSerifSectionHeader(_)`, `GoldengoAmountText(_, role:)` all match Phases 1–5.

## Definition of done

- `swift test` green (386), zero warnings.
- All eight secondary sheets reskinned: GoldGlyphBadge focal glyphs, serif titles/headers, GoldButton CTAs, tokens; Edit uses SelectableChip + matching paid-from; Import success is gold + haptic; Currency picker has a selected wash + empty-results state.
- Every behavior preserved (rituals, Settings scheduling, Import, Edit save/delete, Currency selection).
- Visual-tuning items flagged.
