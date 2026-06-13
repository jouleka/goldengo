# Goldengo UI Rewrite — Phase 7: Widgets + Control Center — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development / executing-plans. NOTE: the widget target is an Xcode-only extension (`AppProject/Widget/`) — it is NOT built by `swift test`. Verification is `xcodebuild` of the `GoldengoWidgetExtension` scheme on a simulator (baseline already confirmed BUILD SUCCEEDED). A `swift test` pass does NOT verify these changes.

**Goal:** Bring the widgets/Control to Quiet-luxe parity within their hard constraints — lock-screen accessory + Control Center render system-tinted/monochrome (gold won't show there), so the only full-color surface is the `GoldengoWidget` systemSmall home-screen tile. Apply the glyph parity (D11) everywhere and the gold accent + tabular figures on that one tile.

**Architecture:** No new file (the project is generated via `project.rb`; a new file might not be in the target's build phase). The gold color is a file-private constant inside the existing `GoldengoWidget.swift` (the extension links Core/Data/Intents, not GoldengoDesignSystem). Static gold (`#B68A2E`) — dark-mode tile shows the light gold, acceptable for a single tile accent (lock-screen is monochrome regardless).

**Spec:** §6 + D11. Builds on Phases 1–6.

**Branch:** `ui-rewrite-quiet-luxe`.

---

## Changes

- **`AppProject/Widget/GoldengoControl.swift`** — `Label("Add expense", systemImage: "plus.circle.fill")` → `systemImage: "plus"` (D11; visual only, `OpenQuickAddIntent` + displayName/description untouched).
- **`AppProject/Widget/GoldengoWidget.swift`**:
  - Add a file-private gold: `private let goldengoWidgetAccent = Color(red: 182/255, green: 138/255, blue: 46/255)` (mirror of locked light gold `#B68A2E`).
  - Tile total `Text(entry.totalText).font(.title2.bold())` → `.font(.title2.bold()).monospacedDigit()` (tabular figures, matching `GoldengoAmountText`).
  - Tile `Label("Add", systemImage: "plus.circle.fill").font(.caption)` → `Label("Add", systemImage: "plus").font(.caption).foregroundStyle(goldengoWidgetAccent)`.
  - Leave the Pocket accessory widget unchanged (lock-screen monochrome; its content/privacy logic is correct and out of scope for color).

## Verification (NOT swift test)

```
cd AppProject && xcodebuild -project Goldengo.xcodeproj -scheme GoldengoWidgetExtension \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`. Also run the full `swift test` (should stay 386/0 — the package is unaffected).

## Definition of done

- Widget extension builds (`xcodebuild` BUILD SUCCEEDED); `swift test` still 386/0.
- Control + tile use the `plus` glyph (parity with the in-app FAB); the tile's "Add" is gold and its total is tabular.
- Pocket/accessory behavior + privacy untouched.
- Known: home-screen tile gold is static (no dark variant) — flag for the simulator pass.
