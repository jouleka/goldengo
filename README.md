# Goldengo

Native iOS personal expense tracker focused on frictionless capture. Logic lives in Swift packages (`swift test` runs the suite headlessly); the iOS app + widget live in `AppProject/`. See `docs/superpowers/specs/` and `docs/superpowers/plans/`.

## Building

- **Logic / tests:** `swift test` (runs headlessly on macOS).
- **App:** the Xcode project is **generated** — run `ruby AppProject/project.rb` to create `AppProject/Goldengo.xcodeproj` (it's git-ignored; **`AppProject/project.rb` is the source of truth — edit that, never the `.pbxproj`**). Then open it in Xcode, or:
  `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' build`

## iCloud / CloudKit

The data store is CloudKit-ready — `GoldengoStore` requests the private database and falls back to a **local-only** store when iCloud isn't provisioned (so unsigned/simulator builds just work). To turn on sync, provision it under your Apple Developer account: in Xcode select the **Goldengo** target → **Signing & Capabilities** → set your **Team**, add the **iCloud** capability with **CloudKit**, and create/select the container **`iCloud.com.goldengo.app`** (add the same App Group + iCloud container to the **GoldengoWidgetExtension** target too).

## Quick capture

Goldengo exposes a **Log Expense** shortcut via `AppShortcutsProvider`, discoverable in the Shortcuts app and by Siri after installing the app.

To wire it to **Back Tap** or the **Action Button** on a real device:

- **Back Tap:** Settings → Accessibility → Touch → Back Tap → Double Tap (or Triple Tap) → select the Goldengo shortcut.
- **Action Button (iPhone 15 Pro / 16):** Settings → Action Button → Shortcuts → select the Goldengo shortcut.

These are physical-device steps and cannot be verified in the simulator.
