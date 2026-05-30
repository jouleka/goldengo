# Goldengo Plan 3c — Polish Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Close the tracked gaps from the Plan 3/3b reviews: make `todayTotal` currency-correct (GOL-34), register the `goldengo://` URL scheme so the widget tap opens Quick-Add (GOL-32), add an iOS 18 Control Center control that opens Quick-Add (GOL-33), and remove dead API.

**Architecture:** Small, surgical changes. The currency fix + cleanup are headless-testable. The URL scheme needs a manual app `Info.plist` (so `CFBundleURLTypes` can be set) — verify the app still launches AND that `xcrun simctl openurl` routes into the app. The Control Center control is a `ControlWidget` added to the existing widget bundle — verify it builds + embeds.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit (Widget + Control), App Intents. Xcode 26.5, iPhone 17 simulator (iOS 26.x supports Control Center controls).

**Out of scope (still tracked open):** GOL-35 lock-screen reveal toggle (needs a Settings surface; amounts are already redacted-by-default).

---

### Task 1: Currency-correct `todayTotal` + remove dead API (GOL-34)

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift`
- Modify: `Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift` (remove unused `formattedAmount`)
- Modify: `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift` (call site)
- Test: `Tests/GoldengoDataTests/ReadMethodsTests.swift` (add a mixed-currency case)

- [ ] **Step 1: Add the failing test** — append to `ReadMethodsTests`:
```swift
    func test_todayTotal_filtersToRequestedCurrency() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        let today = Date.now
        ctx.insert(ExpenseRecord(amount: 100, currencyCode: "ALL", date: today, kind: .expense, source: .manual, dedupeKey: "x"))
        ctx.insert(ExpenseRecord(amount: 50, currencyCode: "EUR", date: today, kind: .expense, source: .manual, dedupeKey: "y"))
        try ctx.save()
        let store = IngestionStore(modelContainer: container)
        let lek = try await store.todayTotal(in: .all)
        let eur = try await store.todayTotal(in: .eur)
        XCTAssertEqual(lek, 100)
        XCTAssertEqual(eur, 50)
    }
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter ReadMethodsTests` → FAIL (no `todayTotal(in:)`).

- [ ] **Step 3: Change `todayTotal` to filter by currency.** Replace the method in `IngestionStore`:
```swift
    /// Sum of today's expense-kind amounts in one currency (avoids mixing currencies).
    public func todayTotal(in currency: CurrencyCode = .all) throws -> Decimal {
        let start = Calendar.current.startOfDay(for: .now)
        let expenseRaw = TransactionKind.expense.rawValue
        let code = currency.rawValue
        let fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw && $0.date >= start && $0.currencyCode == code
        })
        return try modelContext.fetch(fd).reduce(Decimal(0)) { $0 + $1.amount }
    }
```
Update the `logManual` summary line to `let total = try todayTotal(in: currency)`.

- [ ] **Step 4: Update the Recent model call site** — in `RecentExpensesModel.load()`, change `store.todayTotal()` to `store.todayTotal(in: currency)`.

- [ ] **Step 5: Remove dead API** — delete the unused `formattedAmount` computed property from `QuickAddModel`. (Confirm no references: `grep -rn formattedAmount Sources Tests` returns nothing after removal.)

- [ ] **Step 6: Run** — `swift test` → all green (existing `todayTotal` tests still pass via the `.all` default).

- [ ] **Step 7: Commit**
```bash
git add Sources/GoldengoData/IngestionStore.swift Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift Tests/GoldengoDataTests/ReadMethodsTests.swift
git commit -m "fix: filter todayTotal by currency; remove dead formattedAmount (GOL-34)"
```

---

### Task 2: Register `goldengo://` URL scheme (GOL-32)

**Files:**
- Create: `AppProject/Goldengo/Info.plist`
- Modify: `AppProject/project.rb` (use the manual Info.plist on the app target)

- [ ] **Step 1: Create a complete app `Info.plist`** with the URL scheme:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>$(DEVELOPMENT_LANGUAGE)</string>
  <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$(PRODUCT_NAME)</string>
  <key>CFBundleDisplayName</key><string>Goldengo</string>
  <key>CFBundlePackageType</key><string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key>
  <dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.goldengo.app</string>
      <key>CFBundleURLSchemes</key><array><string>goldengo</string></array>
    </dict>
  </array>
</dict>
</plist>
```

- [ ] **Step 2: Point the app target at it in `project.rb`** — in the app target's build-configurations loop, replace the generated-plist settings with:
```ruby
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['INFOPLIST_FILE'] = 'Goldengo/Info.plist'
```
(remove `GENERATE_INFOPLIST_FILE = 'YES'` and `INFOPLIST_KEY_UILaunchScreen_Generation`). Leave the widget target's generated plist as-is.

- [ ] **Step 3: Regenerate + build**
```bash
ruby AppProject/project.rb
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build
```
Expected `** BUILD SUCCEEDED **`. If the plist is missing a key the launch needs, fix it and rebuild.

- [ ] **Step 4: Verify launch AND deep-link routing in the simulator**
```bash
xcrun simctl boot "iPhone 17" 2>/dev/null || true
APP=$(find AppProject/.build -name "Goldengo.app" -path "*Debug-iphonesimulator*" | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.goldengo.app
xcrun simctl io booted screenshot AppProject/.build/launch.png      # confirm app still launches (manual plist didn't break it)
xcrun simctl openurl booted "goldengo://quickadd"
sleep 1
xcrun simctl io booted screenshot AppProject/.build/deeplink.png     # confirm the URL routed → Add tab
```
Read both PNGs: `launch.png` shows the app UI (launch OK), `deeplink.png` shows the **Add** (Quick-Add) tab selected (deep link routed). If `openurl` doesn't route, re-check the scheme registration and `RootView.onOpenURL`.

- [ ] **Step 5: Commit**
```bash
git add AppProject/Goldengo/Info.plist AppProject/project.rb AppProject/Goldengo.xcodeproj/project.pbxproj
git commit -m "feat: register goldengo:// URL scheme so widget/deep-links open Quick-Add (GOL-32)"
```

---

### Task 3: iOS 18 Control Center control (GOL-33)

**Files:**
- Create: `Sources/GoldengoIntents/OpenQuickAddIntent.swift` (a small `AppIntent` that opens the app)
- Create: `AppProject/Widget/GoldengoControl.swift` (the `ControlWidget`)
- Modify: `AppProject/Widget/GoldengoWidget.swift` (add the control to the bundle)
- Test: `Tests/GoldengoIntentsTests/OpenQuickAddIntentTests.swift`

- [ ] **Step 1: Failing test for the open intent's basic shape**

`Tests/GoldengoIntentsTests/OpenQuickAddIntentTests.swift`:
```swift
import XCTest
@testable import GoldengoIntents

@available(iOS 17.0, *)
final class OpenQuickAddIntentTests: XCTestCase {
    func test_intent_hasTitle() {
        XCTAssertFalse(String(localized: OpenQuickAddIntent.title).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter OpenQuickAddIntentTests` → FAIL.

- [ ] **Step 3: Implement the open intent**

`Sources/GoldengoIntents/OpenQuickAddIntent.swift`:
```swift
import AppIntents

/// Opens the app at Quick-Add. Used by the Control Center control.
@available(iOS 17.0, *)
public struct OpenQuickAddIntent: AppIntent {
    public static var title: LocalizedStringResource = "Add Expense"
    public static var openAppWhenRun: Bool = true
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult { .result() }
}
```
> The app's `.onOpenURL`/launch already shows Quick-Add as the first tab; `openAppWhenRun` brings the app forward. (A deep link to force the Add tab can be added later if needed.)

- [ ] **Step 4: Implement the control** (iOS 18)

`AppProject/Widget/GoldengoControl.swift`:
```swift
import WidgetKit
import SwiftUI
import AppIntents
import GoldengoIntents

@available(iOS 18.0, *)
struct GoldengoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "GoldengoQuickAddControl") {
            ControlWidgetButton(action: OpenQuickAddIntent()) {
                Label("Add expense", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Add expense")
        .description("Jump straight to Goldengo Quick-Add.")
    }
}
```

- [ ] **Step 5: Add the control to the widget bundle** — in `GoldengoWidget.swift`, update the bundle to include the control on iOS 18+:
```swift
@main
struct GoldengoWidgetBundle: WidgetBundle {
    var body: some Widget {
        GoldengoWidget()
        if #available(iOS 18.0, *) { GoldengoControl() }
    }
}
```
Add `import GoldengoIntents` to the widget file and ensure the widget extension links `GoldengoIntents` (add the SPM product dep to `widget_target` in `project.rb` alongside `GoldengoData`).

- [ ] **Step 6: Build + verify embed**
```bash
ruby AppProject/project.rb
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build
```
Expected `** BUILD SUCCEEDED **` and `Goldengo.app/PlugIns/GoldengoWidgetExtension.appex` present. (Placing the control in Control Center is a manual device step — build+embed is what's verified here.) `swift test` → green.

- [ ] **Step 7: Commit**
```bash
git add Sources/GoldengoIntents/OpenQuickAddIntent.swift AppProject/Widget/GoldengoControl.swift AppProject/Widget/GoldengoWidget.swift AppProject/project.rb AppProject/Goldengo.xcodeproj/project.pbxproj Tests/GoldengoIntentsTests/OpenQuickAddIntentTests.swift
git commit -m "feat: add iOS 18 Control Center control to open Quick-Add (GOL-33)"
```

---

## Done criteria

- `swift test` green (currency filter + intent test added).
- App builds + **launches** in the iPhone 17 simulator with the manual Info.plist; `simctl openurl goldengo://quickadd` routes to the Add tab (both screenshot-verified).
- Control Center control builds + the widget extension embeds.
- `todayTotal` no longer mixes currencies; dead `formattedAmount` removed.
- Closes GOL-32, GOL-33, GOL-34. GOL-35 (reveal toggle) remains open by design.
