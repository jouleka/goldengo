# Goldengo

Native iOS personal expense tracker focused on frictionless capture. Logic lives in Swift packages (`swift test` runs headlessly); the Xcode app target is added in a later plan. See `docs/superpowers/specs/` and `docs/superpowers/plans/`.

## Quick capture

Goldengo exposes a **Log Expense** shortcut via `AppShortcutsProvider`, discoverable in the Shortcuts app and by Siri after installing the app.

To wire it to **Back Tap** or the **Action Button** on a real device:

- **Back Tap:** Settings → Accessibility → Touch → Back Tap → Double Tap (or Triple Tap) → select the Goldengo shortcut.
- **Action Button (iPhone 15 Pro / 16):** Settings → Action Button → Shortcuts → select the Goldengo shortcut.

These are physical-device steps and cannot be verified in the simulator.
