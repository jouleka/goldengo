# Pocket Truth (cycle 1) — the lock screen claims what's in your pocket

**Status:** design approved (greenlit from ideation round 3; decisions below follow the dossier's assassin guards and the user's standing minimal-steps doctrine).
**Date:** 2026-06-11.
**Origin:** ideation round 3 anchor survivor (`docs/superpowers/ideation/2026-06-11-round-3.md`) — merged from Pocket Truth + Pocket Fog + Named Gaps + Squeeze-and-Settle's reconcile card; passed the day-30 and friction assassins with three required guards.
**Builds on:** wallet v2 (per-currency balances, type-the-balance reconcile, auto-Unaccounted gaps), the existing WidgetKit target + `SharedSummary` refresh plumbing, `RhythmDetector` history, the Sources-tab wallet sheet.

## Goal

The lock screen permanently **asserts** what the books claim is physically in the pocket, per currency — "7 500 L · 60 €". On cash-silent days the claim honestly **fogs** — "~7 500 · losing track since Tue" — the machine confessing *its* blindness, never the user's lapse. One tap lands on the already-shipped type-the-balance numpad; typing reality snaps the fog to ±0 with the drop haptic and books any gap as the existing auto-Unaccounted entry. It never asks anything; it asserts, and reality argues back. The pull rides behaviors that already happen: phone pickups, cash payments, ATM cycles.

## Decision record

- **Surfaces (cycle 1):** a new "Pocket" widget kind with `accessoryInline` (one line above the clock) and `accessoryRectangular` (lock screen + StandBy). The existing home-screen today-total widget is untouched. Home-screen Pocket variant deferred.
- **The claim line:** active currencies' expected balances from `walletBalances` ("7 500 L · 60 €"); rectangular adds the state line (fog or "even since ⟨day⟩"). No baseline yet → "Set your wallet to begin" (tap lands on the wallet sheet).
- **Fog is DETERMINISTIC and capped (assassin guard 1):** `fogWidth(daysSinceReconcile, typicalCashDay)` — pure GoldengoCore math, no model. `typicalCashDay` = median daily cash outflow from the trailing 30 days of wallet-draining expenses (fallback: a small constant when history is thin). **Cap:** once fog exceeds ~one typical wallet (the latest reconciled total), degrade to plain words — "lost track · tap when your wallet's out" — never an absurd ±N that reads as broken. A claim must stay falsifiable from memory or the free-audit loop dies.
- **Currency-aware fog (assassin guard 3):** fog accrues only for currencies with cash *movement history*; a EUR line whose money provably never moves does not fog ("losing track" of static money would be the app lying about its own blindness — the one unforgivable sin).
- **Cash-silent ≠ idle:** fog resets on any reconcile and *narrows* on logged cash activity days (the books moved with the hands); it widens only across days with rhythm-expected cash spend and no entries.
- **Privacy:** the existing "Show amounts on Lock Screen" toggle (default OFF) gates amounts — when off, the widget shows state words only ("even since Tue" / "losing track since Tue"), no numbers. Same key the today-total widget honors.
- **Tap → reconcile (assassin guard 2, adapted):** the widget deep-links straight to the wallet's Adjust screen for the primary (ALL) currency, claim prefilled, numpad focused — the reconcile waits for a wallet-out moment precisely because it lives on the lock screen; nothing ever notifies or nags.
- **Deferred to cycle 2:** the guess chip ("−800 · probably the Tuesday market run"), the ATM-import reconcile card, a home-screen Pocket widget, and Lasts Until (the runway date — same surface, own cycle).

## Components

### 1. `PocketFog` — pure (GoldengoCore)

```swift
public enum PocketFog {
    /// Median daily cash outflow over the trailing window; the fog's growth rate.
    public static func typicalCashDay(dailyOutflows: [Decimal]) -> Decimal   // fallback floor when thin
    /// Fog half-width after `silentDays` without a reconcile, growing by `typicalCashDay`/day,
    /// capped at `walletTotal` (past the cap the UI switches to plain words).
    public static func fogWidth(silentDays: Int, typicalCashDay: Decimal, walletTotal: Decimal) -> Decimal
    public enum Confidence { case even, fogged(width: Decimal), lost }
    public static func confidence(silentDays: Int, typicalCashDay: Decimal, walletTotal: Decimal) -> Confidence
}
```

### 2. Store + shared plumbing (GoldengoData)

- `pocketSnapshot(now:) -> PocketSnapshot` — Sendable: per-currency `{ code, expected, confidence, lastReconcileDate }`, only for currencies with a wallet line; silent-day counting from the latest `WalletCount` per currency and cash-flow dates.
- `SharedSummary` carries the rendered pocket payload for the widget (same pattern as the shared today-total): updated by `refreshSharedTodayTotal`'s existing call sites plus reconciles.

### 3. Widget (AppProject widget target — existing target only, no project regeneration)

- New `PocketWidget` (+ provider/entry/view structs) added INSIDE the existing `AppProject/Widget/GoldengoWidget.swift` and registered in the existing `GoldengoWidgetBundle` — new structs in an existing target file, zero pbxproj edits, the `ruby project.rb` landmine never approached.
- Families: `accessoryInline` ("7 500 L · 60 €" / state words when amounts hidden) and `accessoryRectangular` (claim line + state line + last-reconcile day). Timeline: entry now + daily midnight entries so "losing track since Tue" stays current; reloads on reconcile via the existing WidgetCenter refresh that `logEntry`/saves already trigger.
- Privacy via `.privacySensitive(!reveal)` exactly like the shipped today-total widget, PLUS the words-only fallback content when amounts are hidden.
- `widgetURL` deep link `goldengo://wallet/adjust` → RootView's `onOpenURL` routes to Sources tab + opens the wallet sheet at the ALL Adjust screen.

### 4. App wiring (GoldengoFeatures)

- RootView: handle the new deep link (route to Sources tab, present the wallet sheet, navigate to Adjust(ALL) with the claim prefilled — the prefill already ships).
- Reconcile save already exists; ensure it refreshes the shared pocket payload (drop haptic already ships).

## Error handling / edge cases

- No wallet baseline → inline shows "Set your wallet"; no fog math runs.
- Amounts-hidden toggle → words only, never numbers, in BOTH families.
- Thin history (new currency) → fallback `typicalCashDay` floor; fog grows slowly rather than wildly.
- Negative expected balance (over-logged cash) → show the claim as-is; fog state unchanged — the reconcile fixes it, and hiding it would be fabrication.
- Widget extension reads only `SharedSummary` (App Group) — no store access from the extension process.

## Tests

- **`PocketFogTests` (Core):** zero silent days → even; linear growth; cap → `.lost`; thin-history floor; currency with zero movement history handled by the store (no fog) — pinned at store level.
- **Store (`PocketSnapshotTests`, GoldengoDataTests):** silent-day counting from reconciles and cash entries; activity days narrow/reset; static-currency no-fog; amounts-hidden flag passthrough in the shared payload; snapshot only covers tracked currencies.
- **Widget rendering + deep link + StandBy:** device-verified (the actual point), per the usual split.

## Out of scope (cycle 2 ticket)

Guess chips on gaps; ATM-import reconcile card; home-screen Pocket widget; Lasts Until; Apple Watch.
