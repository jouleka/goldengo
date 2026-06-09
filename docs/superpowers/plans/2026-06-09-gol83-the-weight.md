# The Weight (GOL-83) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make spending feel physical — a firm "drop" haptic the instant any spend is confirmed, and the Provenance source bars smoothly drain when you return to the Sources tab.

**Architecture:** One ~15-line `GoldengoHaptics` helper (GoldengoDesignSystem, `#if canImport(UIKit)` → no-op on macOS) called at the three spend-confirm seams, plus one `.animation(value:)` modifier on the Sources bars. No model/store/data/schema changes.

**Tech Stack:** Swift 6, SwiftUI, UIKit (`UIImpactFeedbackGenerator`). Spec: `docs/superpowers/specs/2026-06-09-the-weight-design.md`.

**Testing note (Rule 12):** haptics + animation are device/visual, not unit-testable. The automated gate is `swift test` staying green + the simulator build succeeding. No faked tests.

---

## File Structure

**Create:** `Sources/GoldengoDesignSystem/GoldengoHaptics.swift`
**Modify:** `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift`, `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`, `Sources/GoldengoFeatures/Provenance/ReceiptReviewView.swift`* , `Sources/GoldengoFeatures/Provenance/SourcesView.swift`

*(`ReceiptReviewView.swift` is under `Sources/GoldengoFeatures/Receipt/` — confirm the path at edit time.)*

---

## Task 1: `GoldengoHaptics` + wire the three spend-confirm seams

**Files:** Create `Sources/GoldengoDesignSystem/GoldengoHaptics.swift`; Modify `QuickAddView.swift`, `RecentExpensesView.swift`, `ReceiptReviewView.swift`.

- [ ] **Step 1: Create the helper**

`Sources/GoldengoDesignSystem/GoldengoHaptics.swift`:

```swift
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// App tactile feedback. `spendLanded` is a brief, firm "drop" — a spend landing (the felt cost
/// cards/totals delete). No-op off UIKit (macOS build/tests) so callers need no platform guard.
public enum GoldengoHaptics {
    public static func spendLanded() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}
```

- [ ] **Step 2: QuickAdd — replace the soft success haptic with the weight drop**

In `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift`, in `.onChange(of: model.savedCount)`, replace the `successHaptic()` call:

```swift
        .onChange(of: model.savedCount) { _, newCount in
            guard newCount > 0 else { return }
            GoldengoHaptics.spendLanded()
            withAnimation(.snappy) { showAdded = true }
```

Then delete the now-unused helper:

```swift
    private func successHaptic() {
#if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
    }
```

- [ ] **Step 3: Recent — fire on ghost confirm + adjust-amount add**

In `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`, the `ghostRow` confirm button:

```swift
        Button { GoldengoHaptics.spendLanded(); Task { await model.confirm(g) } } label: {
```

and the adjust-amount alert's "Add" button:

```swift
                Button("Add") {
                    let amt = Decimal(string: adjustAmount) ?? g.amount
                    GoldengoHaptics.spendLanded()
                    Task { await model.confirm(g, amount: amt) }
                }
```

- [ ] **Step 4: Receipt — fire on Save**

In `Sources/GoldengoFeatures/Receipt/ReceiptReviewView.swift`, the "Save" toolbar button:

```swift
                    Button("Save") {
                        amountFocused = false; merchantFocused = false
                        GoldengoHaptics.spendLanded()
                        Task { await model.save(); onDone() }
                    }
```

- [ ] **Step 5: Build (SPM + simulator)**

Run: `swift build`
Expected: build succeeds (macOS — `GoldengoHaptics` compiles as a no-op).
Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoDesignSystem/GoldengoHaptics.swift Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift Sources/GoldengoFeatures/Recent/RecentExpensesView.swift Sources/GoldengoFeatures/Receipt/ReceiptReviewView.swift
git commit -m "feat(gol-83): spend-landed haptic at every confirm seam (QuickAdd/ghost/receipt)"
```

---

## Task 2: Animate the draining source bars

**Files:** Modify `Sources/GoldengoFeatures/Provenance/SourcesView.swift`.

- [ ] **Step 1: Animate the bar on value change**

In `SourcesView`, on the source `ProgressView`:

```swift
                        ProgressView(value: model.fraction(b))
                            .tint(model.color(b))
                            .animation(.snappy, value: model.fraction(b))
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/GoldengoFeatures/Provenance/SourcesView.swift
git commit -m "feat(gol-83): animate source bars draining on the Sources tab"
```

---

## Task 3: Full suite, device verification, ticket

- [ ] **Step 1: Full test suite** — `swift test` → all 254 still green (no regression; this change adds no tests but must not break the build/suite). Run the FULL suite.

- [ ] **Step 2: Device build + install**

```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath AppProject/.build-device build
xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E AppProject/.build-device/Build/Products/Debug-iphoneos/Goldengo.app
```

- [ ] **Step 3: Manual device verification** — logging an expense (QuickAdd / a ghost tap / a receipt Save) fires a firm "drop" haptic; adding income fires nothing; opening the Sources tab after spending shows the affected source's bar smoothly draining from its old level.

- [ ] **Step 4: Ticket** — set GOL-83 → To Verify with a summary comment.

- [ ] **Step 5: Finish the branch** — second-Opus review over the diff → ff-merge to `main` → push.

---

## Self-Review

**Spec coverage:** `GoldengoHaptics.spendLanded` (Task 1 step 1) ✓; wired into QuickAdd/ghost/receipt (Task 1 steps 2–4) ✓; income silent (no call added to `AddIncomeView`) ✓; animated draining bars (Task 2) ✓; no model/store/schema change (none touched) ✓; device-verified, suite-green gate (Task 3) ✓. Out-of-scope items (moment-of-spend visual, home object, income refill, per-source intensity) absent by construction.

**Placeholder scan:** none — every step has concrete code/commands. (`ReceiptReviewView.swift` path flagged to confirm at edit time — it lives in `Sources/GoldengoFeatures/Receipt/`.)

**Type consistency:** `GoldengoHaptics.spendLanded()` is called identically at all four sites; it takes no args and returns Void; it's `public` in GoldengoDesignSystem, which all four views already import. No new types/signatures elsewhere.
