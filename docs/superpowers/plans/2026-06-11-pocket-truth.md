# Pocket Truth, Cycle 1 (GOL-98) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The lock screen asserts the per-currency pocket balance with honest, capped fog on cash-silent days; one tap deep-links into the shipped type-the-balance reconcile.

**Architecture:** Pure fog math + a Codable widget payload in GoldengoCore; the store composes a `PocketPayload` (both revealed and hidden variants, pre-formatted text) into `SharedSummary` on every save via the existing `refreshSharedTodayTotal` choke point; a new `PocketWidget` (structs added INSIDE the existing `GoldengoWidget.swift` — zero pbxproj edits) renders it; `goldengo://wallet` deep-links through the existing pendingTab pattern into the wallet's Adjust screen.

**Tech Stack:** Swift 6, WidgetKit (accessoryInline/accessoryRectangular), App Group UserDefaults, XCTest. Spec: `docs/superpowers/specs/2026-06-11-pocket-truth-design.md`.

**Hard rules:** full `swift test` before green claims (baseline 359; this plan adds 8 → 367). No Decimal in `#Predicate`. macOS-buildable. NEVER touch `project.rb` or add files to the AppProject targets.

**Branch:** `git checkout -b gol-98-pocket-truth` off `main` before Task 1.

---

### Task 1: Pure core — `PocketFog` + `PocketPayload`

**Files:**
- Create: `Sources/GoldengoCore/PocketFog.swift`
- Test: Create `Tests/GoldengoCoreTests/PocketFogTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import GoldengoCore

final class PocketFogTests: XCTestCase {
    func test_typicalCashDay_isMedianWithFloor() {
        XCTAssertEqual(PocketFog.typicalCashDay(dailyOutflows: [200, 800, 400], floor: 100), 400)
        XCTAssertEqual(PocketFog.typicalCashDay(dailyOutflows: [50, 60], floor: 300), 300,
                       "Thin/low history never makes fog grow absurdly slowly relative to the wallet")
        XCTAssertEqual(PocketFog.typicalCashDay(dailyOutflows: [], floor: 250), 250)
    }

    func test_confidence_states() {
        // Day zero: the books were just reconciled — the claim is exact.
        XCTAssertEqual(PocketFog.confidence(silentDays: 0, typicalCashDay: 500, walletTotal: 7000), .even)
        // Linear growth: 3 silent days at ~500/day → ±1500.
        XCTAssertEqual(PocketFog.confidence(silentDays: 3, typicalCashDay: 500, walletTotal: 7000),
                       .fogged(width: 1500))
        // Cap (assassin guard 1): past ~one wallet the ±N is meaningless — degrade to plain words.
        XCTAssertEqual(PocketFog.confidence(silentDays: 20, typicalCashDay: 500, walletTotal: 7000), .lost)
        // Zero/negative wallet with silence: nothing falsifiable to claim → lost, not ±0.
        XCTAssertEqual(PocketFog.confidence(silentDays: 2, typicalCashDay: 500, walletTotal: 0), .lost)
        // No movement rate (static currency handled store-side, but the math is safe anyway).
        XCTAssertEqual(PocketFog.confidence(silentDays: 5, typicalCashDay: 0, walletTotal: 7000), .even)
    }

    func test_payload_codableRoundTrip() throws {
        let p = PocketPayload(revealedInline: "7 500 L · 60 €", hiddenInline: "even since Tue",
                              revealedLines: ["7 500 L — even since Tue", "60 € — even"],
                              hiddenLines: ["Lek — even since Tue", "Euro — even"],
                              hasWallet: true)
        let decoded = try JSONDecoder().decode(PocketPayload.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter PocketFogTests 2>&1 | grep -E "error:|Executed" | head -3`
Expected: COMPILE FAILURE — `cannot find 'PocketFog' in scope`

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Pure pocket-claim confidence math (GOL-98). The store owns record selection; this owns
/// the honesty band: how blurry the claim is after N cash-silent days, capped so the claim
/// always stays falsifiable from memory (assassin guard: an absurd ±N reads as broken).
public enum PocketFog {
    public enum Confidence: Equatable, Sendable {
        case even                      // reconciled or books moving with the hands
        case fogged(width: Decimal)    // honest ± band
        case lost                      // past ~one wallet of drift — plain words, no number
    }

    /// Median daily cash outflow, floored — thin or tiny history must not make fog crawl.
    public static func typicalCashDay(dailyOutflows: [Decimal], floor: Decimal) -> Decimal {
        guard !dailyOutflows.isEmpty else { return floor }
        let sorted = dailyOutflows.sorted()
        return max(sorted[sorted.count / 2], floor)
    }

    public static func confidence(silentDays: Int, typicalCashDay: Decimal,
                                  walletTotal: Decimal) -> Confidence {
        guard silentDays > 0, typicalCashDay > 0 else { return .even }
        guard walletTotal > 0 else { return .lost }
        let width = typicalCashDay * Decimal(silentDays)
        return width >= walletTotal ? .lost : .fogged(width: width)
    }
}

/// Pre-rendered widget content (GOL-98) — the widget process reads ONLY this from the App
/// Group; all formatting and privacy variants are composed app-side (the today-total pattern).
public struct PocketPayload: Codable, Equatable, Sendable {
    public var revealedInline: String
    public var hiddenInline: String
    public var revealedLines: [String]
    public var hiddenLines: [String]
    public var hasWallet: Bool
    public init(revealedInline: String, hiddenInline: String,
                revealedLines: [String], hiddenLines: [String], hasWallet: Bool) {
        self.revealedInline = revealedInline; self.hiddenInline = hiddenInline
        self.revealedLines = revealedLines; self.hiddenLines = hiddenLines; self.hasWallet = hasWallet
    }
}
```

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter PocketFogTests 2>&1 | grep -E "error:|Executed" | head -3`
Expected: 3 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/PocketFog.swift Tests/GoldengoCoreTests/PocketFogTests.swift
git commit -m "feat(gol-98): pocket fog math + widget payload"
```

---

### Task 2: Store — `pocketSnapshot` + shared payload refresh

**Files:**
- Create: `Sources/GoldengoData/IngestionStore+Pocket.swift`
- Modify: `Sources/GoldengoData/SharedSummary.swift` (payload round-trip), `Sources/GoldengoData/IngestionStore.swift:241-249` (`refreshSharedTodayTotal` also refreshes the pocket payload)
- Test: Create `Tests/GoldengoDataTests/PocketSnapshotTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class PocketSnapshotTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    func test_freshReconcile_isEven() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(7000, currency: .all, tally: nil, at: day(2026, 6, 10))
        let lines = try await store.pocketSnapshot(now: day(2026, 6, 10, hour: 18))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.currencyCode, "ALL")
        XCTAssertEqual(lines.first?.expected, 7000)
        XCTAssertEqual(lines.first?.confidence, .even)
    }

    func test_silentDaysWithMovementHistory_fog() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(7000, currency: .all, tally: nil, at: day(2026, 6, 1))
        // Movement history: cash spends on the 2nd and 3rd (~500/day median).
        _ = try await store.logManual(amount: 500, currency: .all, merchant: "Pazar",
                                      categoryName: nil, date: day(2026, 6, 2))
        _ = try await store.logManual(amount: 500, currency: .all, merchant: "Kafe",
                                      categoryName: nil, date: day(2026, 6, 3))
        // Then silence: last book movement Jun 3, now Jun 6 → 3 silent days.
        let lines = try await store.pocketSnapshot(now: day(2026, 6, 6))
        guard case .fogged(let width)? = lines.first?.confidence else {
            return XCTFail("3 silent days with movement history must fog, got \(String(describing: lines.first?.confidence))")
        }
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThan(width, 6000, "Capped well under one wallet at 3 days")
    }

    func test_cashEntry_resetsTheSilence() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(7000, currency: .all, tally: nil, at: day(2026, 6, 1))
        _ = try await store.logManual(amount: 500, currency: .all, merchant: "Pazar",
                                      categoryName: nil, date: day(2026, 6, 5))
        let lines = try await store.pocketSnapshot(now: day(2026, 6, 5, hour: 20))
        XCTAssertEqual(lines.first?.confidence, .even,
                       "The books moved with the hands today — the claim is current")
    }

    func test_staticCurrency_neverFogs() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(200, currency: .eur, tally: nil, at: day(2026, 6, 1))
        // No EUR cash movement EVER → fogging would be the app lying about its own blindness.
        let lines = try await store.pocketSnapshot(now: day(2026, 6, 9))
        let eur = lines.first { $0.currencyCode == "EUR" }
        XCTAssertEqual(eur?.confidence, .even)
    }

    func test_sharedPayload_writtenOnSave_andRoundTrips() async throws {
        let suite = "pocket-test-\(UUID().uuidString)"
        let summary = SharedSummary(suiteName: suite)
        let p = PocketPayload(revealedInline: "7 500 L", hiddenInline: "even",
                              revealedLines: ["7 500 L — even"], hiddenLines: ["Lek — even"], hasWallet: true)
        summary.writePocketPayload(p)
        XCTAssertEqual(summary.readPocketPayload(), p)
        XCTAssertNil(SharedSummary(suiteName: "pocket-empty-\(UUID().uuidString)").readPocketPayload())
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter PocketSnapshotTests 2>&1 | grep -E "error:|Executed" | head -3`
Expected: COMPILE FAILURE — `no member 'pocketSnapshot'`

- [ ] **Step 3: Implement**

`SharedSummary.swift` — add near the ritual keys:

```swift
    // GOL-98: the pocket widget's pre-rendered content (revealed + hidden variants).
    public static let pocketPayloadKey = "pocketPayload"
    public func writePocketPayload(_ p: PocketPayload) {
        defaults.set((try? JSONEncoder().encode(p)) ?? Data(), forKey: Self.pocketPayloadKey)
    }
    public func readPocketPayload() -> PocketPayload? {
        guard let data = defaults.data(forKey: Self.pocketPayloadKey),
              let p = try? JSONDecoder().decode(PocketPayload.self, from: data) else { return nil }
        return p
    }
```

`IngestionStore+Pocket.swift`:

```swift
import Foundation
import SwiftData
import GoldengoCore

/// One pocket-claim line (GOL-98). Sendable snapshot across the actor boundary.
public struct PocketLine: Sendable, Equatable {
    public var currencyCode: String
    public var expected: Decimal
    public var confidence: PocketFog.Confidence
    public var lastMovement: Date          // latest of: reconcile, any wallet cash flow
}

extension IngestionStore {
    /// The pocket claim per tracked currency. Fog accrues only while the books sit still for
    /// a currency that HAS movement history — static money never fogs (the app must not
    /// confess blindness about money that provably didn't move).
    public func pocketSnapshot(now: Date = .now) throws -> [PocketLine] {
        let balances = try walletBalances(now: now)
        guard !balances.isEmpty else { return [] }
        let expenseRaw = TransactionKind.expense.rawValue
        let manualRaw = ExpenseSource.manual.rawValue
        let driftPrefix = Self.driftKeyPrefix + ":"
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let lookback = cal.date(byAdding: .day, value: -60, to: now) else { return [] }

        return try balances.map { b in
            let code = b.currencyCode
            // Wallet-draining cash spends for this currency, trailing 60 days (tombstones
            // excluded: deleted entries are not movement). Decimal math in memory only.
            let rows = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
                predicate: #Predicate {
                    $0.isArchived == false && $0.currencyCode == code
                        && $0.kindRaw == expenseRaw && $0.date >= lookback
                }))
            let cashSpends = rows.filter {
                !$0.dedupeKey.hasPrefix(driftPrefix)
                    && ($0.fundedBySourceID == FundingPin.wallet
                        || ($0.fundedBySourceID == nil && $0.sourceRaw == manualRaw))
            }
            let lastMovement = max(b.baselineDate, cashSpends.map(\.date).max() ?? .distantPast)
            let silentDays = cal.dateComponents([.day], from: lastMovement, to: now).day ?? 0
            // Static currency: no movement history → never fogs.
            guard !cashSpends.isEmpty else {
                return PocketLine(currencyCode: code, expected: b.expectedNow,
                                  confidence: .even, lastMovement: lastMovement)
            }
            // Median daily outflow over days that HAD outflow; floor = wallet lasting ~a month.
            let byDay = Dictionary(grouping: cashSpends) { cal.startOfDay(for: $0.date) }
                .values.map { $0.reduce(Decimal(0)) { $0 + abs($1.amount) } }
            let typical = PocketFog.typicalCashDay(dailyOutflows: byDay,
                                                   floor: max(b.expectedNow / 30, 1))
            let confidence = PocketFog.confidence(silentDays: silentDays,
                                                  typicalCashDay: typical,
                                                  walletTotal: b.expectedNow)
            return PocketLine(currencyCode: code, expected: b.expectedNow,
                              confidence: confidence, lastMovement: lastMovement)
        }
    }

    /// Compose and persist the widget payload (both privacy variants, pre-formatted).
    func refreshSharedPocket(now: Date = .now) throws {
        let lines = try pocketSnapshot(now: now)
        let summary = SharedSummary()
        guard !lines.isEmpty else {
            summary.writePocketPayload(PocketPayload(
                revealedInline: "Set your wallet", hiddenInline: "Set your wallet",
                revealedLines: [], hiddenLines: [], hasWallet: false))
            return
        }
        func state(_ l: PocketLine) -> String {
            let since = l.lastMovement.formatted(.dateTime.weekday(.abbreviated))
            switch l.confidence {
            case .even: return "even since \(since)"
            case .fogged: return "losing track since \(since)"
            case .lost: return "lost track — tap when your wallet's out"
            }
        }
        func amount(_ l: PocketLine) -> String {
            let money = Money(amount: l.expected, currency: CurrencyCode(l.currencyCode)).formatted()
            if case .fogged = l.confidence { return "~" + money }
            if case .lost = l.confidence { return Money(amount: l.expected, currency: CurrencyCode(l.currencyCode)).formatted() }
            return money
        }
        let name: (String) -> String = { code in
            code == "ALL" ? "Lek" : (Locale.current.localizedString(forCurrencyCode: code) ?? code)
        }
        summary.writePocketPayload(PocketPayload(
            revealedInline: lines.map { amount($0) }.joined(separator: " · "),
            hiddenInline: state(lines[0]),
            revealedLines: lines.map { amount($0) + " — " + state($0) },
            hiddenLines: lines.map { name($0.currencyCode) + " — " + state($0) },
            hasWallet: true))
    }
}
```

`IngestionStore.swift` — extend `refreshSharedTodayTotal` (every save path already funnels here):

```swift
        SharedSummary().writeTodayTotal(Money(amount: total, currency: display).formatted())
        try? refreshSharedPocket()   // GOL-98: the pocket claim rides the same choke point
```

(insert before the `#if canImport(WidgetKit)` block; `try?` — a pocket-compose failure must never block a save.)

NOTE: `setWalletBalance` saves via `modelContext.save()` without `logEntry` — check whether it calls `refreshSharedTodayTotal`; if not, add `try? refreshSharedPocket()` (and the WidgetCenter reload) at the end of `setWalletBalance` so reconciles refresh the lock screen immediately.

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter PocketSnapshotTests 2>&1 | grep -E "error:|Executed" | head -3`
Expected: 5 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData Tests/GoldengoDataTests/PocketSnapshotTests.swift
git commit -m "feat(gol-98): pocket snapshot + shared payload on every save"
```

---

### Task 3: Widget + deep link

Device-verified; the suite + sim build gate the task.

**Files:**
- Modify: `AppProject/Widget/GoldengoWidget.swift` (PocketWidget structs INSIDE this file + bundle registration — never add files to the target), `Sources/GoldengoData/SharedSummary.swift` (pendingWalletAdjust flag), `Sources/GoldengoFeatures/RootView.swift` (deep-link route), `Sources/GoldengoFeatures/Provenance/SourcesView.swift` (consume the flag), `Sources/GoldengoFeatures/Provenance/WalletView.swift` (programmatic Adjust open)

- [ ] **Step 1: Widget structs (append to `GoldengoWidget.swift`, register in the bundle)**

```swift
// MARK: - Pocket Truth (GOL-98): the lock screen claims what's in your pocket.

struct PocketEntry: TimelineEntry { let date: Date; let payload: PocketPayload?; let reveal: Bool }

struct PocketProvider: TimelineProvider {
    func placeholder(in c: Context) -> PocketEntry {
        .init(date: .now, payload: SharedSummary().readPocketPayload(), reveal: false)
    }
    func getSnapshot(in c: Context, completion: @escaping (PocketEntry) -> Void) {
        let s = SharedSummary()
        completion(.init(date: .now, payload: s.readPocketPayload(), reveal: s.read().revealOnLockScreen))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<PocketEntry>) -> Void) {
        let s = SharedSummary()
        let payload = s.readPocketPayload()
        let reveal = s.read().revealOnLockScreen
        let now = Date.now
        // One entry per upcoming midnight so "since Tue" stays honest even without app opens;
        // saves/reconciles reload all timelines anyway (existing WidgetCenter call).
        let cal = Calendar.current
        let entries = (0..<3).compactMap { offset -> PocketEntry? in
            guard let d = cal.date(byAdding: .day, value: offset, to: now) else { return nil }
            return PocketEntry(date: offset == 0 ? now : cal.startOfDay(for: d), payload: payload, reveal: reveal)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct PocketWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: PocketEntry
    var body: some View {
        let payload = entry.payload
        Group {
            if family == .accessoryInline {
                Text(payload.map { entry.reveal ? $0.revealedInline : $0.hiddenInline } ?? "Set your wallet")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    if let payload, payload.hasWallet {
                        ForEach((entry.reveal ? payload.revealedLines : payload.hiddenLines).prefix(3),
                                id: \.self) { line in
                            Text(line).font(.caption2).minimumScaleFactor(0.7).lineLimit(1)
                        }
                    } else {
                        Text("In your pocket").font(.caption2).foregroundStyle(.secondary)
                        Text("Set your wallet to begin").font(.caption2)
                    }
                }
            }
        }
        .privacySensitive(!entry.reveal)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "goldengo://wallet"))
    }
}

struct PocketWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PocketWidget", provider: PocketProvider()) { entry in
            PocketWidgetView(entry: entry)
        }
        .configurationDisplayName("In your pocket")
        .description("What the books say you're carrying — tap to set it straight.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular])
    }
}
```

and in `GoldengoWidgetBundle.body`, after `GoldengoWidget()`: add `PocketWidget()`.

- [ ] **Step 2: Deep link + flag**

`SharedSummary.swift`:

```swift
    // GOL-98: one-shot flag — the pocket widget tap should land ON the Adjust screen.
    public static let pendingWalletAdjustKey = "pendingWalletAdjust"
    public func setPendingWalletAdjust(_ on: Bool) { defaults.set(on, forKey: Self.pendingWalletAdjustKey) }
    public func readPendingWalletAdjust() -> Bool { defaults.bool(forKey: Self.pendingWalletAdjustKey) }
```

`RootView.swift` — in `onOpenURL`, before the generic tab routing:

```swift
            } else if url.host == "wallet" {
                SharedSummary().setPendingWalletAdjust(true)   // GOL-98: land on Adjust
                route(toTab: 5)
            } else if let tab = Self.tab(forDeepLink: url) {
```

`SourcesView.swift` — consume the flag on appearance/foreground (add next to the existing `.task`):

```swift
            .task { await model.load(); consumePendingWalletAdjust() }
            .onChange(of: scenePhase) { _, p in if p == .active { consumePendingWalletAdjust() } }
```

with `@Environment(\.scenePhase) private var scenePhase`, `@State private var walletAutoAdjust = false`, and:

```swift
    private func consumePendingWalletAdjust() {
        let summary = SharedSummary()
        guard summary.readPendingWalletAdjust() else { return }
        summary.setPendingWalletAdjust(false)
        walletAutoAdjust = true
        showCount = true
    }
```

passing it down: `WalletView(model: model, autoOpenAdjust: walletAutoAdjust ? .all : nil)` (and reset `walletAutoAdjust = false` in the sheet's onDismiss). NOTE: the existing `.task` line already calls `await model.load()` — merge, don't duplicate.

`WalletView.swift` — programmatic Adjust:

```swift
    let autoOpenAdjust: CurrencyCode?
    @State private var adjustPresented = false
    public init(model: SourcesModel, autoOpenAdjust: CurrencyCode? = nil) {
        _model = State(initialValue: model); self.autoOpenAdjust = autoOpenAdjust
    }
```

inside the `NavigationStack`'s `List`, add (once):

```swift
            .navigationDestination(isPresented: $adjustPresented) {
                AdjustWalletView(model: model, currency: autoOpenAdjust ?? .all)
            }
            .onAppear { if autoOpenAdjust != nil { adjustPresented = true } }
```

- [ ] **Step 3: Full suite + simulator build**

Run: `swift test 2>&1 | grep -E "Executed [0-9]{3} tests|error:" | tail -2`
Expected: 367 tests, 0 failures.

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add AppProject/Widget/GoldengoWidget.swift Sources
git commit -m "feat(gol-98): pocket widget + wallet deep link"
```

---

### After the plan

Standard cycle: adversarial review of `git diff main...HEAD`, fix confirmed findings, ff-merge, push, device build + install, GOL-98 → **To Verify**.
