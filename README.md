# Goldengo

Native iOS personal expense tracker focused on frictionless capture. Logic lives in Swift packages (`swift test` runs the suite headlessly); the iOS app + widget live in `AppProject/`. See `docs/superpowers/specs/` and `docs/superpowers/plans/`.

## Building

- **Logic / tests:** `swift test` (runs headlessly on macOS).
- **App:** the Xcode project is **generated** — run `ruby AppProject/project.rb` to create `AppProject/Goldengo.xcodeproj` (it's git-ignored; **`AppProject/project.rb` is the source of truth — edit that, never the `.pbxproj`**). Then open it in Xcode, or:
  `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' build`

## iCloud / CloudKit

The data store is CloudKit-ready — `GoldengoStore` requests the private database and falls back to a **local-only** store when iCloud isn't provisioned (so unsigned/simulator builds just work). The SwiftData schema is CloudKit-valid (every relationship has an inverse). Turning on sync is a provisioning step, done as part of running on a real device (below).

## Running on your iPhone (and turning on iCloud sync)

These steps install the app on a real device and enable iCloud sync. They require a **paid Apple Developer Program** membership — CloudKit, App Groups, and push all need it. (A free Apple ID can't provision those; the app still runs local-only without them.)

1. **Generate + open the project:** `ruby AppProject/project.rb`, then `open AppProject/Goldengo.xcodeproj`.
2. **Sign both targets.** For **Goldengo** *and* **GoldengoWidgetExtension** → **Signing & Capabilities**:
   - Tick **Automatically manage signing** and pick your **Team**.
   - The entitlements are already baked in by `project.rb` — iCloud + CloudKit container **`iCloud.com.goldengo.app`**, App Group **`group.com.goldengo.app`**, and push (`aps-environment`). Xcode registers the App IDs and builds the provisioning profiles. If the iCloud container shows as unregistered, click the refresh/＋ to create it (or create it at developer.apple.com → **Identifiers → iCloud Containers**).
   - Bundle IDs: `com.goldengo.app` (app), `com.goldengo.app.widget` (widget).
3. **Sign the iPhone into iCloud** (Settings → your name). The app uses your **private** CloudKit database, so your data stays in your own iCloud account.
4. **Enable Developer Mode** (first time, iOS 16+): Settings → Privacy & Security → **Developer Mode** → on → reboot.
5. **Run:** connect the iPhone (trust the Mac), select it as the run destination in Xcode, press **⌘R**. If prompted on the phone, trust the developer profile: Settings → General → **VPN & Device Management**.
6. The app installs and launches. It starts empty (the demo seed only runs behind the `GOLDENGO_SEED_SAMPLE` env flag) — add an expense or import a statement.

**Verify sync:** add an expense, then check **CloudKit Dashboard** (icloud.developer.apple.com → `iCloud.com.goldengo.app` → **Private Database**, Development env) — records appear shortly. Or run on a second device on the same iCloud account; entries sync automatically (SwiftData ↔ CloudKit, no manual step). For **TestFlight/App Store**, deploy the schema once in CloudKit Dashboard (**Development → Deploy Schema Changes to Production**).

**Troubleshooting:** a "local-only store" warning in the DEBUG console means the iCloud/App Group entitlement isn't active — expected in the Simulator; on device it means signing didn't include the capability (re-check step 2 and that your team has a paid membership). If the widget doesn't share data, confirm the App Group is on **both** targets.

## Quick capture

Goldengo exposes a **Log Expense** App Shortcut (`AppShortcutsProvider`), so you can log an expense **without opening the app** from any trigger you like. When triggered it shows a **category list** (Groceries, Food, …) to pick from, then asks the **amount**, saves to your default currency, and shows a quick confirmation — the app never opens.

You pick the trigger (Goldengo hardcodes none):

- **Action Button (iPhone 15 Pro and later):** Settings → **Action Button** → Shortcut → **Log Expense** (App Shortcuts bind here directly).
- **Siri / Spotlight:** say or search *"Log an expense in Goldengo"*. Also appears in the **Shortcuts** app and as a **Home/Lock-Screen / Control Center** widget action.
- **Back Tap** (and any device without an Action Button): Back Tap only lists shortcuts from the **Shortcuts app**, so wrap it once — Shortcuts → **＋** → add the **Log Expense** action → name it → then bind it under Settings → Accessibility → Touch → **Back Tap** → Double/Triple Tap.

These are physical-device steps and cannot be verified in the simulator.
