# GOL-83 follow-up — CoreHaptics "drop" transient for the spend haptic

**Status:** design approved (user's standing "do what you can yourself" — the feel itself is the verification gate).
**Date:** 2026-06-10.
**Origin:** the feel-refinement noted when GOL-83 shipped: `UIImpactFeedbackGenerator(.rigid)` is a single hard tick; the intended feel is a *drop* — a firm landing with a soft settle.
**Builds on:** `GoldengoHaptics.spendLanded()` (GoldengoDesignSystem), called from QuickAdd, Recent ghosts (Rhythm + GOL-92 Due), Receipt review, Morning/Evening rituals.

## Goal

`spendLanded()` plays a two-beat CoreHaptics pattern that reads as a coin landing in a jar: a strong, fairly sharp transient (the landing) followed ~90 ms later by a soft, dull transient (the settle). Anywhere CoreHaptics can't play — no hardware support, engine failure, macOS — it degrades to the exact current `.rigid` impact, so the change can never make feedback worse.

## Decision record

- **Two `.hapticTransient` events, no continuous events:** landing (intensity 1.0, sharpness 0.65, t=0) + settle (intensity 0.45, sharpness 0.25, t=0.09 s). Tunable constants; the user feel-tests on device and we iterate the four numbers if needed.
- **One shared lazy `CHHapticEngine`** with `isAutoShutdownEnabled` (idle engines sleep; `start()` before each play wakes them) — creating an engine per tap costs milliseconds and audio-session churn on a hot path (every logged spend).
- **`@MainActor` isolation** for the enum: the shared engine is mutable static state under Swift 6 strict concurrency, and every call site is a SwiftUI button action (already MainActor).
- **Any CoreHaptics error → drop the engine (recreate next tap) and fall back to `.rigid` for this tap.** Fail-soft, never silent-dead.
- **No unit tests:** the helper contains no decision logic — only platform calls behind `#if canImport` guards. The macOS suite proves the no-op path compiles; the feel is device-verified (the actual point of the change).

## Out of scope

- Distinct haptics per amount size or per surface (one spend feel, everywhere).
- Audio accompaniment.
