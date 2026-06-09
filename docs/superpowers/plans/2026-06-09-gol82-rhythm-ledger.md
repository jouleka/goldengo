# The Rhythm Ledger (GOL-82) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect recurring DAILY cash spends and pre-draft greyed one-tap "ghost" entries in a "Today's usuals" strip on Home, so the daily logging chore becomes a single tap.

**Architecture:** A pure `RhythmDetector` (GoldengoCore) finds active daily per-merchant patterns (recency-gated, conservative). `IngestionStore` computes ghosts each read (suppressing anything already logged today; never stored) and confirms one via `logManual`. The Home model/view gain a ghost strip. `SubscriptionDetector` is untouched.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest. Reuses `TransactionOccurrence`, `MerchantNormalizer`, `logManual`. Spec: `docs/superpowers/specs/2026-06-09-rhythm-ledger-design.md`.

**Cross-platform:** all cross-platform (no iOS-only API except `.keyboardType`, guarded). `Decimal` math in plain Swift, never in a `#Predicate`.

---

## File Structure

**Create:**
- `Sources/GoldengoCore/RhythmDetector.swift` — `RhythmPattern`, `RhythmDetector` (pure).
- `Sources/GoldengoData/IngestionStore+Rhythm.swift` — `RhythmGhost`, `rhythmGhosts`, `confirmRhythmGhost`.
- `Tests/GoldengoCoreTests/RhythmDetectorTests.swift`
- `Tests/GoldengoDataTests/RhythmGhostTests.swift`

**Modify:**
- `Sources/GoldengoData/RecentExpensesReading.swift` — add `rhythmGhosts` + `confirmRhythmGhost`.
- `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift` — `ghosts` + `confirm`.
- `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift` — the "Today's usuals" strip.

---

## Task 1: `RhythmDetector` (pure core)

**Files:** Create `Sources/GoldengoCore/RhythmDetector.swift`; Test `Tests/GoldengoCoreTests/RhythmDetectorTests.swift`.

- [ ] **Step 1: Write the failing tests** — create `Tests/GoldengoCoreTests/RhythmDetectorTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class RhythmDetectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private func opts() -> RhythmDetector.Options { .init(now: now) }
    /// An occurrence `daysAgo` before `now` (UTC-day aligned enough for the detector).
    private func occ(_ daysAgo: Int, amount: Decimal, merchant: String = "Coffee") -> TransactionOccurrence {
        TransactionOccurrence(id: "o\(daysAgo)-\(merchant)", date: now.addingTimeInterval(Double(-daysAgo) * 86_400),
                              amount: amount, currency: .all, merchant: merchant)
    }

    func test_detectsStrongDailyPattern() {
        let series = (0...7).map { occ($0, amount: 200) }   // 8 consecutive days, ending today
        let p = RhythmDetector.detect(series, options: opts())
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.first?.amount, 200)
        XCTAssertEqual(p.first?.normalizedMerchant, "COFFEE")
        XCTAssertGreaterThanOrEqual(p.first?.confidence ?? 0, 0.6)
    }

    func test_medianAmount_whenAmountsVary() {
        // amounts 180,200,200,200,220,200,200 → median 200
        let amts: [Decimal] = [180, 200, 200, 200, 220, 200]
        let series = amts.enumerated().map { occ($0.offset, amount: $0.element) }
        XCTAssertEqual(RhythmDetector.detect(series, options: opts()).first?.amount, 200)
    }

    func test_rejectsWeekly() {
        let series = [0, 7, 14, 21].map { occ($0, amount: 200) }   // gap 7
        XCTAssertTrue(RhythmDetector.detect(series, options: opts()).isEmpty)
    }

    func test_rejectsTooFewOccurrences() {
        let series = (0...3).map { occ($0, amount: 200) }   // only 4 days (< 6)
        XCTAssertTrue(RhythmDetector.detect(series, options: opts()).isEmpty)
    }

    func test_rejectsStale_notActive() {
        // 8 daily occurrences, but the most recent was 10 days ago → not "due today".
        let series = (10...17).map { occ($0, amount: 200) }
        XCTAssertTrue(RhythmDetector.detect(series, options: opts()).isEmpty)
    }

    func test_rejectsSporadic_lowRegularity() {
        // median gap 1 but a big irregular gap → low regularity → below confidence floor.
        let series = [occ(0, amount: 200), occ(1, amount: 200), occ(2, amount: 200),
                      occ(3, amount: 200), occ(4, amount: 200), occ(12, amount: 200)]
        XCTAssertTrue(RhythmDetector.detect(series, options: opts()).isEmpty)
    }

    func test_recencyWindow_excludesOldOccurrences() {
        // 8 daily occurrences but all >21 days ago → outside the window → nothing.
        let series = (30...37).map { occ($0, amount: 200) }
        XCTAssertTrue(RhythmDetector.detect(series, options: opts()).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'RhythmDetectorTests'`
Expected: FAIL — `cannot find 'RhythmDetector' in scope`.

- [ ] **Step 3: Implement the detector** — create `Sources/GoldengoCore/RhythmDetector.swift`:

```swift
import Foundation

/// One active daily-recurring spend pattern, "due today". Pure value type.
public struct RhythmPattern: Sendable, Equatable, Identifiable {
    public let id: String                 // "<normalizedMerchant>|<currencyCode>"
    public let displayName: String
    public let normalizedMerchant: String
    public let amount: Decimal             // median of recent positive amounts
    public let currency: CurrencyCode
    public let occurrenceCount: Int        // distinct recent days
    public let lastSeen: Date
    public let confidence: Double          // 0...1
    public init(id: String, displayName: String, normalizedMerchant: String, amount: Decimal,
                currency: CurrencyCode, occurrenceCount: Int, lastSeen: Date, confidence: Double) {
        self.id = id; self.displayName = displayName; self.normalizedMerchant = normalizedMerchant
        self.amount = amount; self.currency = currency; self.occurrenceCount = occurrenceCount
        self.lastSeen = lastSeen; self.confidence = confidence
    }
}

/// Pure, on-device DAILY rhythm detection — separate from `SubscriptionDetector` (which floors at
/// weekly). Conservative on purpose: a wrong daily ghost erodes trust.
public enum RhythmDetector {
    public struct Options: Sendable {
        public var windowDays: Int
        public var minOccurrences: Int
        public var maxGap: Int
        public var activeWithinDays: Int
        public var minConfidence: Double
        public var now: Date
        public init(windowDays: Int = 21, minOccurrences: Int = 6, maxGap: Int = 2,
                    activeWithinDays: Int = 2, minConfidence: Double = 0.6, now: Date = .now) {
            self.windowDays = windowDays; self.minOccurrences = minOccurrences; self.maxGap = maxGap
            self.activeWithinDays = activeWithinDays; self.minConfidence = minConfidence; self.now = now
        }
    }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    public static func detect(_ occurrences: [TransactionOccurrence], options: Options = .init()) -> [RhythmPattern] {
        let windowStart = calendar.date(byAdding: .day, value: -options.windowDays, to: options.now) ?? options.now
        var groups: [String: [TransactionOccurrence]] = [:]
        for o in occurrences where o.date >= windowStart {
            let norm = MerchantNormalizer.normalize(o.merchant)
            guard !norm.isEmpty else { continue }
            groups["\(norm)|\(o.currency.rawValue)", default: []].append(o)
        }
        return groups.compactMap { pattern(key: $0.key, raw: $0.value, options: options) }
            .sorted { $0.confidence > $1.confidence }
    }

    private static func pattern(key: String, raw: [TransactionOccurrence], options: Options) -> RhythmPattern? {
        let norm = MerchantNormalizer.normalize(raw.first?.merchant)
        guard !norm.isEmpty else { return nil }
        let currency = raw.first!.currency
        // Collapse same UTC day to one (keep the larger amount) — daily means one per day.
        var byDay: [Date: TransactionOccurrence] = [:]
        for o in raw {
            let d = calendar.startOfDay(for: o.date)
            if let e = byDay[d] { if o.amount > e.amount { byDay[d] = o } } else { byDay[d] = o }
        }
        let series = byDay.values.sorted { $0.date < $1.date }
        guard series.count >= options.minOccurrences else { return nil }

        let lastSeen = series.last!.date
        guard let activeCutoff = calendar.date(byAdding: .day, value: -options.activeWithinDays, to: options.now),
              lastSeen >= activeCutoff else { return nil }

        var gaps: [Int] = []
        for i in 1..<series.count {
            gaps.append(calendar.dateComponents([.day], from: series[i - 1].date, to: series[i].date).day ?? 0)
        }
        let sortedGaps = gaps.sorted()
        guard sortedGaps[sortedGaps.count / 2] == 1 else { return nil }            // daily median
        guard gaps.filter({ $0 <= options.maxGap }).count >= max(1, gaps.count * 2 / 3) else { return nil }

        let positive = series.map(\.amount).filter { $0 > 0 }.sorted()
        guard !positive.isEmpty else { return nil }
        let amount = positive[positive.count / 2]

        let gd = gaps.map(Double.init)
        let mean = gd.reduce(0, +) / Double(gd.count)
        let variance = gd.reduce(0) { $0 + pow($1 - mean, 2) } / Double(gd.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 1
        let regularity = max(0, 1 - cv)
        let occWeight = min(1.0, Double(series.count) / 8.0)
        let confidence = min(1, max(0, 0.6 * regularity + 0.4 * occWeight))   // matches SubscriptionDetector
        guard confidence >= options.minConfidence else { return nil }

        let displayName = series.reversed().compactMap { $0.merchant?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? norm
        return RhythmPattern(id: key, displayName: displayName, normalizedMerchant: norm, amount: amount,
                             currency: currency, occurrenceCount: series.count, lastSeen: lastSeen, confidence: confidence)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'RhythmDetectorTests'`
Expected: PASS (all 7).

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/RhythmDetector.swift Tests/GoldengoCoreTests/RhythmDetectorTests.swift
git commit -m "feat(gol-82): RhythmDetector — pure daily cash-rhythm detection (conservative, recency-gated)"
```

---

## Task 2: Ghost computation + confirm (store)

**Files:** Create `Sources/GoldengoData/IngestionStore+Rhythm.swift`; Test `Tests/GoldengoDataTests/RhythmGhostTests.swift`.

- [ ] **Step 1: Write the failing tests** — create `Tests/GoldengoDataTests/RhythmGhostTests.swift`:

```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class RhythmGhostTests: XCTestCase {
    /// Log `days` consecutive daily coffees ending today, via logManual back-dating.
    private func seedDailyCoffee(_ store: IngestionStore, days: Int, startDaysAgo: Int) async throws {
        for k in stride(from: startDaysAgo, through: 1, by: -1) {
            try await store.logManual(amount: 200, currency: .all, merchant: "Coffee",
                                      categoryName: nil, date: Date().addingTimeInterval(Double(-k) * 86_400))
        }
        _ = days
    }

    func test_rhythmGhosts_surfacesDailyPattern() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store, days: 7, startDaysAgo: 7)   // yesterday..7d ago, all daily
        let ghosts = try await store.rhythmGhosts()
        XCTAssertEqual(ghosts.first?.displayName, "Coffee")
        XCTAssertEqual(ghosts.first?.amount, 200)
    }

    func test_rhythmGhosts_excludesAlreadyLoggedToday() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store, days: 7, startDaysAgo: 7)
        // Log today's coffee already.
        try await store.logManual(amount: 200, currency: .all, merchant: "Coffee", categoryName: nil, date: .now)
        let ghosts = try await store.rhythmGhosts()
        XCTAssertFalse(ghosts.contains { $0.normalizedMerchant == "COFFEE" },
                       "Already logged today → no ghost (no double-count).")
    }

    func test_confirmRhythmGhost_logsExpenseAtAmountToday() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store, days: 7, startDaysAgo: 7)
        let before = try await store.expenseCount()
        let ghost = try await store.rhythmGhosts().first!
        try await store.confirmRhythmGhost(ghost, amount: ghost.amount)
        XCTAssertEqual(try await store.expenseCount(), before + 1)
        let recent = try await store.recentExpenses(limit: 1).first
        XCTAssertEqual(recent?.merchantName, "Coffee")
        XCTAssertEqual(recent?.amount, 200)
        XCTAssertEqual(recent?.source, .manual)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'RhythmGhostTests'`
Expected: FAIL — no `rhythmGhosts` / `confirmRhythmGhost`.

- [ ] **Step 3: Implement** — create `Sources/GoldengoData/IngestionStore+Rhythm.swift`:

```swift
import Foundation
import SwiftData
import GoldengoCore

/// A pre-drafted daily "usual" — surfaced on Home for one-tap confirm. Computed, never stored.
public struct RhythmGhost: Sendable, Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let normalizedMerchant: String
    public let amount: Decimal
    public let currencyCode: String
    public let categoryName: String?     // learned default (for the row icon); nil → generic
}

extension IngestionStore {
    /// Today's pre-drafted "usuals": active daily patterns NOT yet logged today. Computed each call.
    public func rhythmGhosts(now: Date = .now) throws -> [RhythmGhost] {
        let expenseRaw = TransactionKind.expense.rawValue
        let expenses = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.kindRaw == expenseRaw }))
        let occurrences = expenses.map {
            TransactionOccurrence(id: $0.dedupeKey, date: $0.date, amount: abs($0.amount),
                                  currency: CurrencyCode($0.currencyCode), merchant: $0.merchantName)
        }
        let patterns = RhythmDetector.detect(occurrences, options: .init(now: now))

        // Merchants already logged today (local day) → suppress (no double-count).
        let startOfToday = Calendar.current.startOfDay(for: now)
        let loggedTodayMerchants = Set(expenses
            .filter { $0.date >= startOfToday }
            .map { MerchantNormalizer.normalize($0.merchantName) })

        return patterns.compactMap { p in
            guard !loggedTodayMerchants.contains(p.normalizedMerchant) else { return nil }
            return RhythmGhost(id: p.id, displayName: p.displayName, normalizedMerchant: p.normalizedMerchant,
                               amount: p.amount, currencyCode: p.currency.rawValue,
                               categoryName: try? learnedCategoryName(forNormalized: p.normalizedMerchant))
        }
    }

    /// Confirm a ghost: log it as a normal manual expense at `amount`, today. Reuses the full
    /// logManual path (auto-category via categoryName:nil, subscription-link, widget refresh).
    public func confirmRhythmGhost(_ ghost: RhythmGhost, amount: Decimal) throws {
        try logManual(amount: amount, currency: CurrencyCode(ghost.currencyCode),
                      merchant: ghost.displayName, categoryName: nil, date: .now)
    }

    /// Read-only learned category for a normalized merchant (does NOT bump merchant stats — unlike
    /// the private defaultCategory used at log time).
    private func learnedCategoryName(forNormalized norm: String) throws -> String? {
        guard !norm.isEmpty else { return nil }
        var mf = FetchDescriptor<MerchantRecord>(predicate: #Predicate { $0.normalizedName == norm })
        mf.fetchLimit = 1
        return try modelContext.fetch(mf).first?.defaultCategory?.name
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'RhythmGhostTests'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/IngestionStore+Rhythm.swift Tests/GoldengoDataTests/RhythmGhostTests.swift
git commit -m "feat(gol-82): rhythmGhosts (computed, suppress-already-logged) + confirmRhythmGhost"
```

---

## Task 3: Reading protocol + Home model

**Files:** Modify `Sources/GoldengoData/RecentExpensesReading.swift`, `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift`; Test `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift` (extend, or create if absent — check first).

- [ ] **Step 1: Write the failing test** — append to `Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift` (create the file with this content if it doesn't exist):

```swift
import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class RhythmGhostModelTests: XCTestCase {
    private func seedDailyCoffee(_ store: IngestionStore) async throws {
        for k in stride(from: 7, through: 1, by: -1) {
            try await store.logManual(amount: 200, currency: .all, merchant: "Coffee",
                                      categoryName: nil, date: Date().addingTimeInterval(Double(-k) * 86_400))
        }
    }

    func test_load_populatesGhosts() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store)
        let model = RecentExpensesModel(store: store, currency: .all)
        await model.load()
        XCTAssertEqual(model.ghosts.first?.displayName, "Coffee")
    }

    func test_confirm_logsAndClearsGhost() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store)
        let model = RecentExpensesModel(store: store, currency: .all)
        await model.load()
        let ghost = try XCTUnwrap(model.ghosts.first)
        await model.confirm(ghost)
        XCTAssertFalse(model.ghosts.contains { $0.normalizedMerchant == ghost.normalizedMerchant },
                       "Confirmed → logged today → ghost gone on reload.")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'RhythmGhostModelTests'`
Expected: FAIL — `RecentExpensesModel` has no `ghosts` / `confirm`; reader has no `rhythmGhosts`.

- [ ] **Step 3: Extend the reading protocol** — in `Sources/GoldengoData/RecentExpensesReading.swift`, add two requirements inside the protocol:

```swift
    func rhythmGhosts(now: Date) async throws -> [RhythmGhost]
    func confirmRhythmGhost(_ ghost: RhythmGhost, amount: Decimal) async throws
```

(`IngestionStore` already satisfies these via the `+Rhythm` extension — its `throws` actor methods fulfill the `async throws` requirements, exactly like `recentExpenses`.)

- [ ] **Step 4: Add ghosts to the model** — in `Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift`:

(a) Add the stored property after `public private(set) var loadFailed = false`:

```swift
    public private(set) var ghosts: [RhythmGhost] = []
```

(b) In `load()`, after `summary = try await reader.dashboardSummary(...)`, load ghosts (non-fatal):

```swift
            ghosts = (try? await reader.rhythmGhosts(now: .now)) ?? []
```

(c) Add a confirm method (after `delete`/`restore`):

```swift
    /// Confirm a daily "usual": log it at `amount` (default = its median), then reload so it clears.
    public func confirm(_ ghost: RhythmGhost, amount: Decimal? = nil) async {
        try? await reader.confirmRhythmGhost(ghost, amount: amount ?? ghost.amount)
        await load()
    }
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter 'RhythmGhostModelTests'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoData/RecentExpensesReading.swift Sources/GoldengoFeatures/Recent/RecentExpensesModel.swift Tests/GoldengoFeaturesTests/RecentExpensesModelTests.swift
git commit -m "feat(gol-82): RecentExpensesModel exposes ghosts + confirm (reading-protocol additions)"
```

---

## Task 4: "Today's usuals" strip on Home

**Files:** Modify `Sources/GoldengoFeatures/Recent/RecentExpensesView.swift`.

- [ ] **Step 1: Add adjust state** — add to `RecentExpensesView`'s `@State`s (near `showCurrencyPicker`):

```swift
    @State private var adjusting: RhythmGhost?
    @State private var adjustAmount = ""
```

- [ ] **Step 2: Insert the strip into the List** — in `body`, between the categories card and the `GoldengoSectionLabel("Recent")`:

```swift
                if let s = model.summary, !s.topCategories.isEmpty { categoriesCard(s).goldengoCardRow() }

                if !model.ghosts.isEmpty {
                    GoldengoSectionLabel("Today's usuals")
                        .goldengoCardRow(top: GoldengoTheme.Spacing.m, bottom: GoldengoTheme.Spacing.xs)
                    ForEach(model.ghosts) { g in ghostRow(g) }
                }

                GoldengoSectionLabel("Recent")
```

- [ ] **Step 3: Add the ghost row + adjust alert** — add `ghostRow` near `expenseRow`, and attach the alert in `body` (e.g. right after `.refreshable { await model.load() }`):

Row builder:

```swift
    private func ghostRow(_ g: RhythmGhost) -> some View {
        Button { Task { await model.confirm(g) } } label: {
            HStack(spacing: GoldengoTheme.Spacing.m) {
                Image(systemName: GoldengoCategoryIcon.symbol(for: g.categoryName))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.goldengoField)
                    .clipShape(RoundedRectangle(cornerRadius: GoldengoTheme.Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.displayName).font(.subheadline.weight(.medium))
                    Text("~" + Money(amount: g.amount, currency: CurrencyCode(g.currencyCode)).formatted() + " · tap to add")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle").foregroundStyle(GoldengoTheme.accent)
            }
            .padding(.vertical, 4)
            .opacity(0.7)   // reads as a draft
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: GoldengoTheme.Spacing.xs, leading: GoldengoTheme.Spacing.m,
                                  bottom: GoldengoTheme.Spacing.xs, trailing: GoldengoTheme.Spacing.m))
        .contextMenu {
            Button("Adjust amount…") { adjustAmount = ""; adjusting = g }
        }
    }
```

Alert modifier (attach to the `NavigationStack` content, e.g. after `.refreshable`):

```swift
            .alert("Adjust amount", isPresented: Binding(get: { adjusting != nil },
                                                         set: { if !$0 { adjusting = nil } }),
                   presenting: adjusting) { g in
                TextField("Amount", text: $adjustAmount)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                Button("Add") {
                    let amt = Decimal(string: adjustAmount) ?? g.amount
                    Task { await model.confirm(g, amount: amt) }
                }
                Button("Cancel", role: .cancel) { }
            } message: { g in
                Text("How much for \(g.displayName) today?")
            }
```

- [ ] **Step 4: Build for the simulator**

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/Recent/RecentExpensesView.swift
git commit -m "feat(gol-82): Today's usuals strip on Home (1-tap confirm + adjust amount)"
```

---

## Task 5: Full suite, device verification, ticket

- [ ] **Step 1: Full test suite** — `swift test` → all green (existing 242 + new RhythmDetector/RhythmGhost/RhythmGhostModel tests). Run the FULL suite (the GOL-79 lesson — `recentExpenses`/model changed). Fix anything red.

- [ ] **Step 2: Device build + install**

```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath AppProject/.build-device build
xcrun devicectl device install app --device 7B8F5F4F-B6B9-5A41-926D-31C29770064E AppProject/.build-device/Build/Products/Debug-iphoneos/Goldengo.app
```

- [ ] **Step 3: Manual device verification** — log the same merchant (e.g. "Coffee" 200) on ~6 consecutive days (back-date via Edit if needed) → a "Today's usuals" strip appears on Home with "Coffee · ~200 · tap to add"; one tap logs it (today) and the ghost disappears; logging it manually first means no ghost shows; "Adjust amount…" lets you log a different amount. Confirm a weekly-only merchant produces NO ghost.

- [ ] **Step 4: Ticket** — set GOL-82 → To Verify with a summary comment (what shipped, test counts, the device checklist).

- [ ] **Step 5: Finish the branch** — second-Opus review over the diff → ff-merge to `main` → push.

---

## Self-Review

**Spec coverage:** RhythmDetector daily/recency/conservative (Task 1) ✓; RhythmGhost + computed-not-stored + suppress-already-logged + confirm-via-logManual (Task 2) ✓; protocol + model ghosts/confirm (Task 3) ✓; Home strip + 1-tap + adjust (Task 4) ✓; SubscriptionDetector untouched (no edits to it anywhere) ✓; Decimal never in #Predicate (predicates filter isArchived/kindRaw/normalizedName only; all amount/gap math in plain Swift) ✓; out-of-scope items (weekly+, stored ghosts, explicit dismiss, rich editor) absent by construction.

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** `RhythmPattern`/`RhythmDetector.Options`/`detect(_:options:)` consistent Tasks 1–2; `RhythmGhost(id:displayName:normalizedMerchant:amount:currencyCode:categoryName:)` consistent Tasks 2–4; `rhythmGhosts(now:)` + `confirmRhythmGhost(_:amount:)` match across store, protocol, and model; `RecentExpensesModel.ghosts` + `confirm(_:amount:)` match the view; `learnedCategoryName(forNormalized:)` is read-only (no stat mutation, unlike the log-time `defaultCategory`). `MerchantRecord.normalizedName`/`.defaultCategory` match the usage in `IngestionStore.defaultCategory`.
```
