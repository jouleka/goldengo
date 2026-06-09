# GOL-83 — The Weight (spend lands: haptic + animated source drain)

**Ticket:** [GOL-83](https://mysigner.youtrack.cloud/issue/GOL-83).
**Status:** design approved; pending spec review.
**Date:** 2026-06-09.
**Origin:** standout #3 (the "felt cost" layer) from the ultracode ideation — scoped, per the ideation's own conflict note, as an **enhancement to Provenance (GOL-81)**, NOT a competing home-screen object.
**Builds on:** the Provenance Sources screen (`SourcesView`/`SourceBalance`, GOL-81), the spend-confirm seams in `QuickAddView`, `RecentExpensesView` (ghost confirm), `ReceiptReviewView`.

## Goal

Make spending feel physical — restore the felt cost that cards/totals delete. The instant any spend is confirmed, a brief firm "drop" **haptic** lands it; and on the Sources tab, the affected source's bar **smoothly drains** from its old fill to the new lower one.

## Decision record (brainstorm)

- **Scope = haptic on every spend-confirm + animated draining bars** (chosen over a moment-of-spend visual on the Add screen, and over a dedicated home physical object). Smallest, on-brand, builds directly on GOL-81, no new screen and no Add↔FIFO coupling. The dedicated home object was explicitly advised against by the ideation (it would compete with the Home dashboard).
- **Spend-only** — income (`AddIncomeView`) stays silent in v1; loss-aversion by design (a gentle "refill" feel is a noted follow-up).
- **Device-verified, not test-driven** — haptics + animation aren't meaningfully unit-testable; the automated gate is "package builds + full suite stays green" (Rule 12: no faked tests).

## Components

### 1. `GoldengoHaptics` — `Sources/GoldengoDesignSystem/GoldengoHaptics.swift` (new, ~20 lines)
```
public enum GoldengoHaptics {
    /// A brief, firm "drop" — a spend landing. CoreHaptics sharp transient when available,
    /// UIImpactFeedbackGenerator(.rigid) fallback. No-op off UIKit (macOS build/tests).
    public static func spendLanded()
}
```
Body wrapped in `#if canImport(UIKit)` so it compiles as a no-op on macOS and callers need no guard. Implementation: try a one-shot `CHHapticEngine` transient (sharpness high, intensity ~0.8); on failure/unsupported, `UIImpactFeedbackGenerator(style: .rigid).impactOccurred()`. Exact feel tuned with the frontend-design skill at implementation time.

### 2. Wire into the three spend-confirm seams (GoldengoFeatures)
- **`QuickAddView`** — replace the existing `.success` notification haptic (in `.onChange(of: model.savedCount)`) with `GoldengoHaptics.spendLanded()`. (The "Added" toast stays.)
- **`RecentExpensesView`** — in `ghostRow`'s confirm action, call `GoldengoHaptics.spendLanded()` alongside `model.confirm(g)` (and on the adjust-amount "Add").
- **`ReceiptReviewView`** — on the "Save" action, call `GoldengoHaptics.spendLanded()`.

### 3. Animated draining bars (GoldengoFeatures)
- In `SourcesView`, add `.animation(.snappy, value: model.fraction(b))` to each source's `ProgressView`. The Sources tab persists in the `TabView` and reloads on entry (`RootView` `onChange` tab 5 → `load()`), so the fraction change animates old → new — a visible drain when you return after spending. One modifier, no new state.

## Data flow
```
confirm a spend (QuickAdd save / ghost tap / receipt Save)
    → logManual/logAutomatic (unchanged) + GoldengoHaptics.spendLanded()   ← the "drop" you feel
open Sources tab → SourcesModel.load() updates the snapshot
    → each ProgressView animates from its prior fill to the new (lower) fill   ← the drain you see
```

## Error handling
- Haptics unavailable (no engine / Low Power Mode / unsupported device) → silent no-op (impact fallback, then nothing). Never blocks logging.
- macOS / non-UIKit → `spendLanded()` is a compiled no-op.

## Tests
- **No new unit tests** — haptics + animation are device/visual. The gate: `swift test` stays green (no regression) and `swift build` + the Xcode simulator build succeed (the new file + view edits compile, incl. macOS no-op). Verified on device for feel.

## Out of scope (explicit, v1)
- A moment-of-spend visual on the Add screen (would couple Add → source/FIFO state).
- A dedicated home-screen physical object (water level / scale) — competes with the Home dashboard.
- Income "refill" haptic/animation.
- Per-source-specific haptic intensity (e.g. tied to how much of a source drained).
