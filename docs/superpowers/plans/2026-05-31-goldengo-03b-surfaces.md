# Goldengo Plan 3b — Capture Surfaces + Recent List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make logging reachable from everywhere and give it visible feedback: a Recent-expenses list (so Quick-Add isn't logging into a void), `LogExpenseIntent` exposed to Siri/Shortcuts/Back Tap/Action Button, and a Home/Lock-Screen widget showing today's total with a one-tap jump to Quick-Add.

**Architecture:** Extend `IngestionStore` with `Sendable`-returning read methods (recent list, today total). Add a `RecentExpenses` feature + a `TabView` app shell. Expose the existing `LogExpenseIntent` via an `AppShortcutsProvider`. Add a WidgetKit extension that reads a small **App Group `UserDefaults` summary** the app writes on each save (avoids SwiftData-in-widget + the lock-screen Data-Protection problem; amounts are redactable). Widget target is added to the generated Xcode project via `project.rb`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, App Intents, WidgetKit, App Groups. Xcode 26.5, iPhone 17 simulator.

**Verification reality:** the Recent list and app shell are screenshot-verifiable in the simulator. The widget and shortcuts **build + embed** are verifiable, but placing a widget / running Back Tap are manual device/Settings actions — those steps say so honestly.

**Deferred:** iOS 18 Control Center control (its own extension; a later micro-plan).

---

### Task 1: Store read methods (recent list + today total)

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift`
- Test: `Tests/GoldengoDataTests/ReadMethodsTests.swift`

- [ ] **Step 1: Extend `ExpenseSnapshot`** (add `date`, `merchantName`) in `IngestionStore.swift`:
```swift
public struct ExpenseSnapshot: Sendable, Equatable {
    public var dedupeKey: String
    public var amount: Decimal
    public var currencyCode: String
    public var source: ExpenseSource
    public var categoryName: String?
    public var date: Date
    public var merchantName: String?
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/GoldengoDataTests/ReadMethodsTests.swift`:
```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class ReadMethodsTests: XCTestCase {
    func test_recentExpenses_returnsAllNonArchived() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 100, currency: .all, merchant: "A", categoryName: nil)
        try await store.logManual(amount: 200, currency: .all, merchant: "B", categoryName: nil)
        let recents = try await store.recentExpenses(limit: 10)
        XCTAssertEqual(recents.count, 2)
        XCTAssertEqual(Set(recents.map(\.amount)), [100, 200])
    }

    func test_todayTotal_sumsTodaysExpenses() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 100, currency: .all, merchant: nil, categoryName: nil)
        try await store.logManual(amount: 250, currency: .all, merchant: nil, categoryName: nil)
        let total = try await store.todayTotal()
        XCTAssertEqual(total, 350)
    }
}
```

- [ ] **Step 3: Run to verify fail** — `swift test --filter ReadMethodsTests` → FAIL.

- [ ] **Step 4: Implement.** Refactor snapshot creation into a private helper and add the read methods to `IngestionStore`:
```swift
    public func recentExpenses(limit: Int = 20) throws -> [ExpenseSnapshot] {
        var fd = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = limit
        return try modelContext.fetch(fd).map(makeSnapshot)
    }

    /// Sum of today's expense-kind amounts. NOTE: assumes the primary currency
    /// (mixed-currency totals are a future concern; see spec §6 ExchangeRate).
    public func todayTotal() throws -> Decimal {
        let start = Calendar.current.startOfDay(for: .now)
        let expenseRaw = TransactionKind.expense.rawValue
        let fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw && $0.date >= start
        })
        return try modelContext.fetch(fd).reduce(Decimal(0)) { $0 + $1.amount }
    }

    private func makeSnapshot(_ r: ExpenseRecord) -> ExpenseSnapshot {
        ExpenseSnapshot(dedupeKey: r.dedupeKey, amount: r.amount, currencyCode: r.currencyCode,
                        source: r.source, categoryName: r.category?.name,
                        date: r.date, merchantName: r.merchantName)
    }
```
Update the existing `snapshot(dedupeKey:)` to `return makeSnapshot(r)`.

- [ ] **Step 5: Run** — `swift test --filter ReadMethodsTests` → PASS; then full `swift test` → green.

- [ ] **Step 6: Commit**
```bash
git add Sources/GoldengoData/IngestionStore.swift Tests/GoldengoDataTests/ReadMethodsTests.swift
git commit -m "feat: add recentExpenses and todayTotal read methods to IngestionStore"
```

---

### Task 2: Recent-expenses list + Tab app shell

**Files:**
- Create: `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift`
- Create: `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`
- Create: `Sources/GoldengoFeatures/RootView.swift`
- Test: `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift`
- Modify: `AppProject/Goldengo/GoldengoApp.swift` (present `RootView`)

- [ ] **Step 1: Write the failing model test**

`Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift`:
```swift
import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class RecentExpensesModelTests: XCTestCase {
    func test_load_populatesRowsAndTodayTotal() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 250, currency: .all, merchant: "Coffee", categoryName: "Coffee")
        let m = RecentExpensesModel(store: store, currency: .all)
        await m.load()
        XCTAssertEqual(m.rows.count, 1)
        XCTAssertEqual(m.todayTotalText, "L 250")
    }
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter RecentExpensesModelTests` → FAIL.

- [ ] **Step 3: Implement the model**

`Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift`:
```swift
import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class RecentExpensesModel {
    public let store: IngestionStore
    public var currency: CurrencyCode
    public private(set) var rows: [ExpenseSnapshot] = []
    public private(set) var todayTotalText: String = ""

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store; self.currency = currency
    }

    public func load() async {
        rows = (try? await store.recentExpenses(limit: 50)) ?? []
        let total = (try? await store.todayTotal()) ?? 0
        todayTotalText = Money(amount: total, currency: currency).formatted()
    }
}
```

- [ ] **Step 4: Run** — `swift test --filter RecentExpensesModelTests` → PASS.

- [ ] **Step 5: Implement the views**

`Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`:
```swift
import SwiftUI
import GoldengoCore
import GoldengoDesignSystem

public struct RecentExpensesView: View {
    @State private var model: RecentExpensesModel
    public init(model: RecentExpensesModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            List {
                Section("Today") { Text(model.todayTotalText).font(.title2.bold()) }
                Section("Recent") {
                    ForEach(model.rows, id: \.dedupeKey) { r in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(r.merchantName ?? r.categoryName ?? "Expense")
                                Text(r.categoryName ?? "Uncategorized").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money(amount: r.amount, currency: CurrencyCode(r.currencyCode)).formatted())
                        }
                    }
                }
            }
            .navigationTitle("Goldengo")
            .task { await model.load() }
        }
    }
}
```

`Sources/GoldengoFeatures/RootView.swift`:
```swift
import SwiftUI
import GoldengoData

public struct RootView: View {
    private let store: IngestionStore
    public init(store: IngestionStore) { self.store = store }

    public var body: some View {
        TabView {
            QuickAddView(model: QuickAddModel(store: store))
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
            RecentExpensesView(model: RecentExpensesModel(store: store))
                .tabItem { Label("Recent", systemImage: "list.bullet") }
        }
    }
}
```

- [ ] **Step 6: Point the app at `RootView`** — in `AppProject/Goldengo/GoldengoApp.swift`, replace the `QuickAddView(...)` body with:
```swift
            RootView(store: GoldengoStore.shared())
                .modelContainer(GoldengoStore.container)
```
(add `import GoldengoFeatures` if not present).

- [ ] **Step 7: Build, run, screenshot, verify** — regenerate not needed (no new target). Build + launch as in Plan 3 Task 7, screenshot the **Recent** tab:
```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build
xcrun simctl boot "iPhone 17" 2>/dev/null || true
APP=$(find AppProject/.build -name "Goldengo.app" -path "*Debug-iphonesimulator*" | head -1)
xcrun simctl install booted "$APP"; xcrun simctl launch booted com.goldengo.app
```
Add an expense via Quick-Add (or pre-seed), switch to Recent, `xcrun simctl io booted screenshot AppProject/.build/recent.png`, read it, confirm the Today total + a recent row render. Iterate if needed.

- [ ] **Step 8: Commit**
```bash
git add Sources/GoldengoFeatures/Recent Sources/GoldengoFeatures/RootView.swift Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift AppProject/Goldengo/GoldengoApp.swift
git commit -m "feat: add Recent-expenses list and tabbed app shell"
```

---

### Task 3: Expose `LogExpenseIntent` to Siri/Shortcuts (enables Back Tap / Action Button)

**Files:**
- Create: `Sources/GoldengoIntents/GoldengoShortcuts.swift`
- Modify: `Sources/GoldengoIntents/LogExpenseIntent.swift` (only if needed for phrases)

- [ ] **Step 1: Add an `AppShortcutsProvider`**

`Sources/GoldengoIntents/GoldengoShortcuts.swift`:
```swift
import AppIntents

@available(iOS 17.0, *)
public struct GoldengoShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: ["Log an expense in \(.applicationName)", "Add a \(.applicationName) expense"],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle"
        )
    }
}
```

- [ ] **Step 2: Build** — `swift build` (the package compiles). The app already links `GoldengoIntents`, so the shortcut registers at launch.

- [ ] **Step 3: Commit**
```bash
git add Sources/GoldengoIntents/GoldengoShortcuts.swift
git commit -m "feat: expose LogExpenseIntent via AppShortcutsProvider for Siri/Shortcuts"
```

- [ ] **Step 4: Document the device-only wiring** — append to `README.md` a short "Quick capture" section: after installing, set **Settings → Accessibility → Touch → Back Tap → Double Tap → (Goldengo shortcut)** and/or assign the **Action Button** to the Goldengo shortcut. (These are user actions on a real device; nothing to verify in the simulator.) Commit the README.

---

### Task 4: Today-total widget (Home + Lock Screen)

**Files:**
- Create: `Sources/GoldengoData/SharedSummary.swift` (App Group `UserDefaults` read/write)
- Modify: `Sources/GoldengoData/IngestionStore.swift` (write summary after each save)
- Modify: `AppProject/Goldengo/GoldengoStore.swift` (App Group container) + entitlements
- Create: `AppProject/Widget/GoldengoWidget.swift`
- Modify: `AppProject/project.rb` (add widget extension target + App Group)
- Test: `Tests/GoldengoDataTests/SharedSummaryTests.swift`

> The widget reads a tiny App Group summary (today total + redaction flag) — NOT SwiftData — so it works on the lock screen without Data-Protection issues. App Group id: `group.com.goldengo.app`.

- [ ] **Step 1: Failing test for the shared summary**

`Tests/GoldengoDataTests/SharedSummaryTests.swift`:
```swift
import XCTest
@testable import GoldengoData

final class SharedSummaryTests: XCTestCase {
    func test_roundTrip_usesStandardDefaultsWhenNoAppGroup() {
        let s = SharedSummary(suiteName: nil)   // falls back to .standard in tests
        s.write(todayTotalText: "L 1,234", redacted: false)
        XCTAssertEqual(s.read().todayTotalText, "L 1,234")
        XCTAssertEqual(s.read().redacted, false)
    }
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter SharedSummaryTests` → FAIL.

- [ ] **Step 3: Implement `SharedSummary`**

`Sources/GoldengoData/SharedSummary.swift`:
```swift
import Foundation

public struct SharedSummary {
    public struct Snapshot: Equatable { public var todayTotalText: String; public var redacted: Bool }
    private let defaults: UserDefaults
    public static let appGroupID = "group.com.goldengo.app"

    public init(suiteName: String? = SharedSummary.appGroupID) {
        defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }
    public func write(todayTotalText: String, redacted: Bool) {
        defaults.set(todayTotalText, forKey: "todayTotalText")
        defaults.set(redacted, forKey: "redacted")
    }
    public func read() -> Snapshot {
        Snapshot(todayTotalText: defaults.string(forKey: "todayTotalText") ?? "—",
                 redacted: defaults.bool(forKey: "redacted"))
    }
}
```

- [ ] **Step 4: Run** — `swift test --filter SharedSummaryTests` → PASS.

- [ ] **Step 5: Write the summary after each manual save** — in `IngestionStore.logManual`, after `try modelContext.save()`, refresh the shared summary:
```swift
        let total = try todayTotal()
        SharedSummary().write(todayTotalText: Money(amount: total, currency: currency).formatted(), redacted: false)
```
(Default `redacted: false`; a Settings toggle for lock-screen redaction is future. Keep it simple here.)

- [ ] **Step 6: App Group container + entitlement.** In `GoldengoStore.swift`, build the container in the App Group so app + widget share it (and so the summary defaults suite resolves on device):
```swift
    public static let container: ModelContainer = {
        let config = ModelConfiguration(groupContainer: .identifier(SharedSummary.appGroupID))
        return (try? ModelContainer(for: goldengoSchema, configurations: config))
            ?? (try! ModelContainer(for: goldengoSchema))   // fallback if entitlement missing in a context
    }()
```

- [ ] **Step 7: Widget**

`AppProject/Widget/GoldengoWidget.swift`:
```swift
import WidgetKit
import SwiftUI
import GoldengoData

struct GoldengoEntry: TimelineEntry { let date: Date; let totalText: String }

struct GoldengoProvider: TimelineProvider {
    func placeholder(in c: Context) -> GoldengoEntry { .init(date: .now, totalText: "L 0") }
    func getSnapshot(in c: Context, completion: @escaping (GoldengoEntry) -> Void) {
        completion(.init(date: .now, totalText: SharedSummary().read().todayTotalText))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<GoldengoEntry>) -> Void) {
        let e = GoldengoEntry(date: .now, totalText: SharedSummary().read().todayTotalText)
        completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(900))))
    }
}

struct GoldengoWidgetView: View {
    var entry: GoldengoEntry
    var body: some View {
        VStack(alignment: .leading) {
            Text("Today").font(.caption).foregroundStyle(.secondary)
            Text(entry.totalText).font(.title2.bold()).minimumScaleFactor(0.6)
            Spacer()
            Label("Add", systemImage: "plus.circle.fill").font(.caption)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "goldengo://quickadd"))
    }
}

@main
struct GoldengoWidgetBundle: WidgetBundle {
    var body: some Widget { GoldengoWidget() }
}

struct GoldengoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GoldengoWidget", provider: GoldengoProvider()) { entry in
            GoldengoWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's spending")
        .description("Today's total — tap to add.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}
```
Also handle the `goldengo://quickadd` deep link in `GoldengoApp` (`.onOpenURL` → select the Add tab).

- [ ] **Step 8: Add the widget extension target in `project.rb`** — add an `:app_extension` target `GoldengoWidgetExtension`, its Swift file, `NSExtensionPointIdentifier = com.apple.widgetkit-extension`, the same App Group entitlement on both app and extension, and embed it in the app (Copy Files → PlugIns). **Iterate** `ruby AppProject/project.rb` → `xcodebuild ... build` until `** BUILD SUCCEEDED **`. The `xcodeproj` gem supports app-extension targets and `add_target_dependency` + an embed phase; adjust to the installed gem's API as needed.

- [ ] **Step 9: Verify build + embed**
```bash
ruby AppProject/project.rb
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build
```
Expected `** BUILD SUCCEEDED **`, and the built `Goldengo.app/PlugIns/` contains `GoldengoWidgetExtension.appex`. (Placing the widget on the home screen / lock screen and the Back-Tap gesture are manual device actions — note that the build+embed is what's verified here.)

- [ ] **Step 10: Commit**
```bash
git add Sources/GoldengoData/SharedSummary.swift Sources/GoldengoData/IngestionStore.swift AppProject Tests/GoldengoDataTests/SharedSummaryTests.swift
git commit -m "feat: add today-total widget (Home + Lock) via App Group summary"
```

---

## Done criteria

- `swift test` green (read methods, recent model, shared summary).
- App builds + runs in the iPhone 17 simulator; **Recent tab screenshot** shows today's total + recent rows.
- `LogExpenseIntent` is exposed via `AppShortcutsProvider` (Siri/Shortcuts discover it; Back Tap / Action Button wireable in Settings — documented).
- Widget extension **builds and embeds** (`.appex` in PlugIns), reads the App Group summary, deep-links to Quick-Add.
- Honestly flagged: widget placement, Control Center, and physical Back Tap/Action Button gestures are manual/device steps, not simulator-verified.
