# Goldengo Plan 3 — Frictionless Capture (core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship the heart of the app — a keypad-first Quick-Add that logs an expense in under two seconds — running in an iOS Simulator, plus the `LogExpenseIntent` that every capture surface reuses.

**Architecture:** Three new SPM targets hold testable logic + SwiftUI (`GoldengoDesignSystem`, `GoldengoFeatures`, `GoldengoIntents`), all depending on the existing `GoldengoCore`/`GoldengoData`/`GoldengoConnectors`. A thin Xcode app target (generated programmatically with the `xcodeproj` Ruby gem — already installed) hosts the SwiftUI app and links the local packages. Verification: `xcodebuild` for an iPhone 17 simulator, then `xcrun simctl` to boot/install/launch and **screenshot** the Quick-Add screen (the screenshot is read back to confirm it renders).

**Tech Stack:** Swift 6, SwiftUI, SwiftData, App Intents, XCTest. Xcode 26.5, iOS 26.x simulators.

**Scope:** Core capture only. **Deferred to Plan 3b:** Lock-Screen/Home widgets, Control Center control, and the Back Tap / Action Button Shortcut setup (those are device-level and build on this intent).

**Design refinement (important):** Manual Quick-Add entries are **always inserted as distinct expenses** (unique dedupe key), because two genuine identical cash purchases on the same day must not collapse. Exact-key dedupe stays for connector/import data; **manual↔import reconciliation becomes a fuzzy match at import time (Plan 5)**, not an exact-key merge. This supersedes the "manual and import share a composite key" wording in the spec §6 — note it when Plan 5 lands.

---

### Task 1: Design system theme

**Files:**
- Modify: `Package.swift` (add `GoldengoDesignSystem` target + test target)
- Create: `Sources/GoldengoDesignSystem/GoldengoTheme.swift`
- Test: `Tests/GoldengoDesignSystemTests/ThemeTests.swift`

- [ ] **Step 1: Add the target to `Package.swift`** — add to `products` and `targets`:
```swift
        .library(name: "GoldengoDesignSystem", targets: ["GoldengoDesignSystem"]),
```
```swift
        .target(name: "GoldengoDesignSystem"),
        .testTarget(name: "GoldengoDesignSystemTests", dependencies: ["GoldengoDesignSystem"]),
```

- [ ] **Step 2: Write the failing test**

`Tests/GoldengoDesignSystemTests/ThemeTests.swift`:
```swift
import XCTest
@testable import GoldengoDesignSystem

final class ThemeTests: XCTestCase {
    func test_goldAccentHex_isStable() {
        XCTAssertEqual(GoldengoTheme.accentGoldHex, "#E8B341")
    }
    func test_spacingScale_isMonotonic() {
        XCTAssertLessThan(GoldengoTheme.Spacing.s, GoldengoTheme.Spacing.m)
        XCTAssertLessThan(GoldengoTheme.Spacing.m, GoldengoTheme.Spacing.l)
    }
}
```

- [ ] **Step 3: Run to verify it fails** — `swift test --filter ThemeTests` → FAIL (no `GoldengoTheme`).

- [ ] **Step 4: Implement the theme**

`Sources/GoldengoDesignSystem/GoldengoTheme.swift`:
```swift
import SwiftUI

public enum GoldengoTheme {
    public static let accentGoldHex = "#E8B341"
    public static var accent: Color { Color(hex: accentGoldHex) }

    public enum Spacing {
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
    }
}

public extension Color {
    init(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, opacity: 1)
    }
}
```

- [ ] **Step 5: Run** — `swift test --filter ThemeTests` → PASS.

- [ ] **Step 6: Commit**
```bash
git add Package.swift Sources/GoldengoDesignSystem Tests/GoldengoDesignSystemTests
git commit -m "feat: add GoldengoDesignSystem theme (gold palette, spacing)"
```

---

### Task 2: Manual logging path on the store

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift`
- Test: `Tests/GoldengoDataTests/LogManualTests.swift`

Manual entries are distinct (unique key) and carry a user-chosen category (find-or-create by name).

- [ ] **Step 1: Write the failing tests**

`Tests/GoldengoDataTests/LogManualTests.swift`:
```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class LogManualTests: XCTestCase {
    func test_logManual_insertsDistinctExpenses_evenWhenIdentical() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2) // two identical coffees are two expenses, not one
    }

    func test_logManual_attachesNamedCategory_findOrCreate() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let key = try await store.logManual(amount: 900, currency: .all, merchant: "Spar", categoryName: "Groceries")
        let snap = try await store.snapshot(dedupeKey: key)
        XCTAssertEqual(snap?.categoryName, "Groceries")
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter LogManualTests` → FAIL (`logManual` missing).

- [ ] **Step 3: Implement `logManual` (returns the new record's dedupeKey)**

Add to `IngestionStore`:
```swift
    /// Logs a user-entered expense. Always a distinct insert (unique key) so identical
    /// same-day purchases are never collapsed. Returns the new record's dedupeKey.
    @discardableResult
    public func logManual(amount: Decimal, currency: CurrencyCode,
                          merchant: String?, categoryName: String?) throws -> String {
        let key = "manual:\(UUID().uuidString)"
        let rec = ExpenseRecord(amount: amount, currencyCode: currency.rawValue, date: .now,
                                merchantName: merchant, kind: .expense, source: .manual, dedupeKey: key)
        if let categoryName, !categoryName.isEmpty {
            rec.category = try findOrCreateCategory(named: categoryName)
        } else {
            rec.category = try defaultCategory(forMerchant: merchant)
        }
        modelContext.insert(rec)
        try modelContext.save()
        return key
    }

    private func findOrCreateCategory(named name: String) throws -> CategoryRecord {
        var fd = FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.name == name })
        fd.fetchLimit = 1
        if let existing = try modelContext.fetch(fd).first { return existing }
        let c = CategoryRecord(name: name)
        modelContext.insert(c)
        return c
    }
```

- [ ] **Step 4: Run** — `swift test --filter LogManualTests` → PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/GoldengoData/IngestionStore.swift Tests/GoldengoDataTests/LogManualTests.swift
git commit -m "feat: add distinct manual-entry logging with find-or-create category"
```

---

### Task 3: Quick-Add view model

**Files:**
- Modify: `Package.swift` (add `GoldengoFeatures` target depending on Core/Data/Connectors/DesignSystem + test target)
- Create: `Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift`
- Test: `Tests/GoldengoFeaturesTests/QuickAddModelTests.swift`

- [ ] **Step 1: Add the target** to `Package.swift`:
```swift
        .library(name: "GoldengoFeatures", targets: ["GoldengoFeatures"]),
```
```swift
        .target(name: "GoldengoFeatures", dependencies: ["GoldengoCore", "GoldengoData", "GoldengoConnectors", "GoldengoDesignSystem"]),
        .testTarget(name: "GoldengoFeaturesTests", dependencies: ["GoldengoFeatures"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/GoldengoFeaturesTests/QuickAddModelTests.swift`:
```swift
import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class QuickAddModelTests: XCTestCase {
    private func makeModel() throws -> QuickAddModel {
        QuickAddModel(store: IngestionStore(modelContainer: try .goldengoInMemory()), currency: .all)
    }

    func test_keypad_buildsAmount_andCanSaveOnlyWhenPositive() throws {
        let m = try makeModel()
        XCTAssertFalse(m.canSave)
        m.tap("1"); m.tap("5"); m.tap("0"); m.tap("0")
        XCTAssertEqual(m.amountString, "1500")
        XCTAssertEqual(m.amountDecimal, 1500)
        XCTAssertTrue(m.canSave)
        m.backspace()
        XCTAssertEqual(m.amountString, "150")
    }

    func test_save_persistsExpense_andResets() async throws {
        let m = try makeModel()
        m.tap("2"); m.tap("5"); m.tap("0")
        m.selectedCategory = "Coffee"
        try await m.save()
        XCTAssertEqual(try await m.store.expenseCount(), 1)
        XCTAssertEqual(m.amountString, "")          // resets for the next entry
    }
}
```

- [ ] **Step 3: Run to verify it fails** — `swift test --filter QuickAddModelTests` → FAIL.

- [ ] **Step 4: Implement the model**

`Sources/GoldengoFeatures/QuickAdd/QuickAddModel.swift`:
```swift
import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class QuickAddModel {
    public let store: IngestionStore
    public var currency: CurrencyCode
    public private(set) var amountString: String = ""
    public var selectedCategory: String?
    public var merchant: String = ""

    /// Most-used categories surfaced as one-tap chips (smart defaults come later).
    public let quickCategories = ["Groceries", "Food", "Transport", "Coffee", "Bills", "Shopping"]

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store
        self.currency = currency
    }

    public var amountDecimal: Decimal { Decimal(string: amountString) ?? 0 }
    public var canSave: Bool { amountDecimal > 0 }
    public var formattedAmount: String { Money(amount: amountDecimal, currency: currency).formatted() }

    public func tap(_ digit: String) {
        guard amountString.count < 12 else { return }
        if amountString.isEmpty && digit == "0" { return }
        amountString.append(digit)
    }

    public func backspace() {
        guard !amountString.isEmpty else { return }
        amountString.removeLast()
    }

    public func save() async throws {
        guard canSave else { return }
        try await store.logManual(amount: amountDecimal, currency: currency,
                                  merchant: merchant.isEmpty ? nil : merchant,
                                  categoryName: selectedCategory)
        reset()
    }

    public func reset() {
        amountString = ""
        merchant = ""
        selectedCategory = nil
    }
}
```

- [ ] **Step 5: Run** — `swift test --filter QuickAddModelTests` → PASS. Then `swift test` (full suite) → green.

- [ ] **Step 6: Commit**
```bash
git add Package.swift Sources/GoldengoFeatures Tests/GoldengoFeaturesTests
git commit -m "feat: add QuickAddModel (keypad amount, category, save)"
```

---

### Task 4: Quick-Add SwiftUI view

**Files:**
- Create: `Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift`

(UI — verified in the simulator in Task 7, not unit-tested.)

- [ ] **Step 1: Implement the view** (keypad-first, amount hero, category chips, Add button)

`Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift`:
```swift
import SwiftUI
import GoldengoDesignSystem

public struct QuickAddView: View {
    @State private var model: QuickAddModel
    public init(model: QuickAddModel) { _model = State(initialValue: model) }

    private let keys = ["1","2","3","4","5","6","7","8","9",".","0","⌫"]

    public var body: some View {
        VStack(spacing: GoldengoTheme.Spacing.l) {
            Text(model.amountString.isEmpty ? "0" : model.amountString)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.top, GoldengoTheme.Spacing.l)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GoldengoTheme.Spacing.s) {
                    ForEach(model.quickCategories, id: \.self) { cat in
                        Button(cat) { model.selectedCategory = cat }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(model.selectedCategory == cat ? GoldengoTheme.accent : Color(.secondarySystemBackground))
                            .foregroundStyle(model.selectedCategory == cat ? .black : .primary)
                            .clipShape(Capsule())
                    }
                }.padding(.horizontal)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: GoldengoTheme.Spacing.s) {
                ForEach(keys, id: \.self) { k in
                    Button { tap(k) } label: {
                        Text(k).font(.title2).frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }.foregroundStyle(.primary)
                }
            }.padding(.horizontal)

            Button {
                Task { try? await model.save() }
            } label: {
                Text("Add").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .background(model.canSave ? GoldengoTheme.accent : Color(.systemGray4))
            .foregroundStyle(.black).clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(!model.canSave).padding(.horizontal).padding(.bottom, GoldengoTheme.Spacing.l)
        }
    }

    private func tap(_ k: String) { k == "⌫" ? model.backspace() : model.tap(k) }
}
```

- [ ] **Step 2: Build the package** — `swift build` → compiles (SwiftUI builds for macOS too; if a UIKit-only symbol is used, gate with `#if canImport(UIKit)`).

- [ ] **Step 3: Commit**
```bash
git add Sources/GoldengoFeatures/QuickAdd/QuickAddView.swift
git commit -m "feat: add keypad-first Quick-Add SwiftUI view"
```

---

### Task 5: `LogExpenseIntent` (App Intents)

**Files:**
- Modify: `Package.swift` (add `GoldengoIntents` target depending on Core/Data + test)
- Create: `Sources/GoldengoIntents/LogExpenseIntent.swift`
- Create: `Sources/GoldengoIntents/ExpenseLogging.swift` (testable core)
- Test: `Tests/GoldengoIntentsTests/ExpenseLoggingTests.swift`

The intent stays thin; the logic lives in a testable function so Siri/Shortcuts/Back Tap all route through verified code.

- [ ] **Step 1: Add the target** to `Package.swift`:
```swift
        .library(name: "GoldengoIntents", targets: ["GoldengoIntents"]),
```
```swift
        .target(name: "GoldengoIntents", dependencies: ["GoldengoCore", "GoldengoData"]),
        .testTarget(name: "GoldengoIntentsTests", dependencies: ["GoldengoIntents"]),
```

- [ ] **Step 2: Write the failing test**

`Tests/GoldengoIntentsTests/ExpenseLoggingTests.swift`:
```swift
import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoIntents

final class ExpenseLoggingTests: XCTestCase {
    func test_logExpense_persistsThroughStore() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = try await ExpenseLogging.log(amount: 1500, currencyCode: "ALL",
                                                   merchant: nil, categoryName: "Groceries", store: store)
        XCTAssertEqual(try await store.expenseCount(), 1)
        XCTAssertTrue(summary.contains("1,500"))
    }
}
```

- [ ] **Step 3: Run to verify it fails** — `swift test --filter ExpenseLoggingTests` → FAIL.

- [ ] **Step 4: Implement the testable core + the intent**

`Sources/GoldengoIntents/ExpenseLogging.swift`:
```swift
import Foundation
import GoldengoCore
import GoldengoData

public enum ExpenseLogging {
    /// Shared logging path for every capture surface. Returns a short confirmation string.
    public static func log(amount: Decimal, currencyCode: String, merchant: String?,
                           categoryName: String?, store: IngestionStore) async throws -> String {
        let currency = CurrencyCode(currencyCode)
        try await store.logManual(amount: amount, currency: currency,
                                  merchant: merchant, categoryName: categoryName)
        return "Logged \(Money(amount: amount, currency: currency).formatted())"
    }
}
```

`Sources/GoldengoIntents/LogExpenseIntent.swift`:
```swift
import AppIntents
import Foundation
import GoldengoCore
import GoldengoData

/// The app sets this at launch so the intent reaches the shared on-disk store
/// WITHOUT the package depending on the app target.
@MainActor public enum IntentEnvironment {
    public static var storeProvider: (@MainActor () -> IngestionStore)?
}

@available(iOS 17.0, *)
public struct LogExpenseIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Expense"
    public static var description = IntentDescription("Quickly log an expense in Goldengo.")

    @Parameter(title: "Amount") public var amount: Double
    @Parameter(title: "Category") public var category: String?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = IntentEnvironment.storeProvider?() else {
            return .result(dialog: "Goldengo isn't ready yet.")
        }
        let summary = try await ExpenseLogging.log(amount: Decimal(amount), currencyCode: "ALL",
                                                   merchant: nil, categoryName: category, store: store)
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}
```
> The package compiles standalone (no app dependency); the app injects `IntentEnvironment.storeProvider` in Task 6. The logic stays covered by the explicit-store `ExpenseLogging.log` test.

- [ ] **Step 5: Run** — `swift test --filter ExpenseLoggingTests` → PASS. (The intent's `perform` is exercised in the app at Task 7; the logic is covered here.)

- [ ] **Step 6: Commit**
```bash
git add Package.swift Sources/GoldengoIntents Tests/GoldengoIntentsTests
git commit -m "feat: add LogExpenseIntent with testable shared logging core"
```

---

### Task 6: Xcode app project (generated) + app shell

**Files:**
- Create: `AppProject/project.rb` (xcodeproj generation script)
- Create: `AppProject/Goldengo/GoldengoApp.swift`
- Create: `AppProject/Goldengo/GoldengoStore.swift`
- Create: `AppProject/Goldengo/Info.plist` (as needed)
- Generated: `AppProject/Goldengo.xcodeproj`

- [ ] **Step 1: App entry + shared store**

`AppProject/Goldengo/GoldengoStore.swift`:
```swift
import Foundation
import SwiftData
import GoldengoData

/// Process-wide SwiftData container + ingestion store for the app and its intents.
@MainActor
public enum GoldengoStore {
    public static let container: ModelContainer = {
        try! ModelContainer(for: ModelContainer.goldengoSchema)   // on-disk; CloudKit wired in a later plan
    }()
    public static func shared() -> IngestionStore { IngestionStore(modelContainer: container) }
}
```

`AppProject/Goldengo/GoldengoApp.swift`:
```swift
import SwiftUI
import GoldengoData
import GoldengoFeatures
import GoldengoIntents

@main
struct GoldengoApp: App {
    init() {
        // Wire the App Intent's store provider to the app's shared container.
        IntentEnvironment.storeProvider = { GoldengoStore.shared() }
    }
    var body: some Scene {
        WindowGroup {
            QuickAddView(model: QuickAddModel(store: GoldengoStore.shared()))
                .modelContainer(GoldengoStore.container)
        }
    }
}
```

- [ ] **Step 2: Write the project generation script**

`AppProject/project.rb`:
```ruby
require 'xcodeproj'
proj_path = File.join(__dir__, 'Goldengo.xcodeproj')
project = Xcodeproj::Project.new(proj_path)

target = project.new_target(:application, 'Goldengo', :ios, '17.0')

# Source files
group = project.main_group.new_group('Goldengo', 'Goldengo')
Dir[File.join(__dir__, 'Goldengo', '*.swift')].each do |f|
  target.add_file_references([group.new_file(File.basename(f))])
end

# Build settings
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.goldengo.app'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
end

# Local SPM package + product deps
pkg = project.root_object.package_references
ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
ref.path = '..'
project.root_object.package_references << ref
%w[GoldengoFeatures GoldengoData GoldengoIntents GoldengoDesignSystem].each do |product|
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.product_name = product
  dep.package = ref
  target.frameworks_build_phase  # ensure phase exists
  target.package_product_dependencies << dep
end

project.save
puts "Generated #{proj_path}"
```
> This is the starting point. **Iterate**: run `ruby AppProject/project.rb`, then `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'generic/platform=iOS Simulator' build`. If the local-package linkage API differs in this `xcodeproj` gem version, adjust (the gem's `XCLocalSwiftPackageReference`/`XCSwiftPackageProductDependency` are the right classes). Keep fixing until it builds. Commit the script and the generated project.

- [ ] **Step 3: Generate + commit**
```bash
ruby AppProject/project.rb
git add AppProject
git commit -m "feat: generate Goldengo iOS app target linking local packages"
```

---

### Task 7: Build, run in the simulator, and verify with a screenshot

- [ ] **Step 1: Build for an iPhone 17 simulator**
```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath AppProject/.build build
```
Expected: `** BUILD SUCCEEDED **`. Fix any compile/linker errors and re-run until it succeeds.

- [ ] **Step 2: Boot the simulator, install, launch**
```bash
xcrun simctl boot "iPhone 17" 2>/dev/null || true
APP=$(find AppProject/.build -name "Goldengo.app" -path "*Debug-iphonesimulator*" | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.goldengo.app
```

- [ ] **Step 3: Screenshot and verify**
```bash
xcrun simctl io booted screenshot AppProject/.build/quickadd.png
```
Read `AppProject/.build/quickadd.png` and confirm the Quick-Add screen renders: amount display, category chips, numeric keypad, Add button. If it doesn't render as expected, fix the view/app wiring and repeat from Step 1.

- [ ] **Step 4: Commit any fixes**
```bash
git add -A
git commit -m "fix: Quick-Add renders correctly in iPhone 17 simulator"
```

---

## Done criteria

- `swift test` green (design system, manual-logging, QuickAddModel, intent logging).
- The app **builds and launches in the iPhone 17 simulator**, and a screenshot confirms the Quick-Add screen renders and is usable.
- `LogExpenseIntent` exists and its logging path is unit-tested.
- Manual entries insert distinctly (no false merges); category find-or-create works.
- Deferred to **Plan 3b**: widgets, Control Center, Back Tap / Action Button Shortcut wiring.
