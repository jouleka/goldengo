# Subscription Auto-Settle (GOL-92) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Confirmed fixed-amount subscriptions get their charges auto-logged when they fall due — `.automatic` source, dated at the due date — so totals are right without any user action; Re-entry stays untouched.

**Architecture:** A pure planner in GoldengoCore derives due-but-unlogged charge dates from the most recent *observed* charge (idempotent by construction — each settled entry becomes the new anchor). A store sweep in GoldengoData logs them via the existing `logEntry` path (`.automatic` so GOL-79 import reconciliation merges later statement rows in). One wiring call in `RootView` on foreground.

**Tech Stack:** Swift 6 strict concurrency, SwiftData `@ModelActor`, XCTest. Spec: `docs/superpowers/specs/2026-06-10-subscription-auto-settle-design.md`.

**Hard rules (from CLAUDE.md / project gotchas):**
- NEVER compare `Decimal` or call captured-array `.contains` inside a `#Predicate` — filter in memory after the fetch.
- Run the FULL `swift test` (never filtered-only) before claiming green. Expected baseline: 292 tests; this plan adds 13 (305 at the end).
- The SPM package also builds for macOS (tests run there) — no iOS-only API in Core/Data.
- Only Sendable snapshots cross the `@ModelActor` boundary.

**Branch:** create `gol-92-auto-settle` off `main` before Task 1 (`git checkout -b gol-92-auto-settle`).

---

### Task 1: `SubscriptionSettlementPlanner` (pure, GoldengoCore)

**Files:**
- Create: `Sources/GoldengoCore/SubscriptionSettlementPlanner.swift`
- Test: `Tests/GoldengoCoreTests/SubscriptionSettlementPlannerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import GoldengoCore

final class SubscriptionSettlementPlannerTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    func test_singleMissedMonthlyCharge() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 5, 5), cadence: .monthly, now: day(2026, 6, 10), calendar: cal)
        XCTAssertEqual(due, [day(2026, 6, 5)])
    }

    func test_nothingDue_whenNextChargeIsInTheFuture() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 6, 5), cadence: .monthly, now: day(2026, 6, 10), calendar: cal)
        XCTAssertEqual(due, [])
    }

    func test_multipleMissedPeriods() {
        // Last charge Apr 12, now Jun 20 → May 12 and Jun 12 both fell due (horizon start Apr 21).
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 4, 12), cadence: .monthly, now: day(2026, 6, 20), calendar: cal)
        XCTAssertEqual(due, [day(2026, 5, 12), day(2026, 6, 12)])
    }

    func test_horizonCutoff_dropsOldMisses() {
        // Last charge Jan 5, now Jun 10 → Feb–Jun 5 all fell due, but only those within
        // the trailing 60 days (≥ Apr 11) are settled: May 5 and Jun 5.
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 1, 5), cadence: .monthly, now: day(2026, 6, 10), calendar: cal)
        XCTAssertEqual(due, [day(2026, 5, 5), day(2026, 6, 5)])
    }

    func test_weeklyCadence() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 6, 1), cadence: .weekly, now: day(2026, 6, 16), calendar: cal)
        XCTAssertEqual(due, [day(2026, 6, 8), day(2026, 6, 15)])
    }

    func test_backwardsClock_yieldsNothing() {
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 6, 10), cadence: .monthly, now: day(2026, 6, 5), calendar: cal)
        XCTAssertEqual(due, [])
    }

    func test_monthEndAnchoring_doesNotDriftAfterShortMonth() {
        // Anchored advance: Jan 31 → Feb 28 → Mar 31 (a charge-by-charge walk would drift to Mar 28).
        let due = SubscriptionSettlementPlanner.dueCharges(
            lastCharge: day(2026, 1, 31), cadence: .monthly, now: day(2026, 4, 10), calendar: cal)
        XCTAssertEqual(due, [day(2026, 2, 28), day(2026, 3, 31)])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SubscriptionSettlementPlannerTests`
Expected: COMPILE FAILURE — `cannot find 'SubscriptionSettlementPlanner' in scope`

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Plans the due-but-unlogged charge dates for a confirmed subscription (GOL-92).
/// Pure: everything derives from the last *observed* charge, so settling is naturally
/// idempotent — each logged charge becomes the new anchor and a re-run yields [].
public enum SubscriptionSettlementPlanner {
    /// Misses older than this are let go: a sub with no observed charge for ~2 monthly
    /// cycles is questionably alive — don't fabricate deep history.
    public static let horizonDays = 60

    /// Charge dates strictly after `lastCharge`, at-or-before `now`, within the trailing
    /// horizon, oldest first. The anchored multi-period advance (`by: k`) keeps the billing
    /// day-of-month stable across short months (Jan 31 → Feb 28 → Mar 31, not Mar 28).
    public static func dueCharges(lastCharge: Date, cadence: SubscriptionCadence,
                                  now: Date, calendar: Calendar) -> [Date] {
        guard lastCharge < now,
              let horizonStart = calendar.date(byAdding: .day, value: -horizonDays, to: now)
        else { return [] }
        var due: [Date] = []
        var k = 1
        var previous = lastCharge
        var next = cadence.advance(lastCharge, by: k, calendar: calendar)
        while next <= now {
            guard next > previous else { return due }   // advance() fell back to its input — never spin
            if next >= horizonStart { due.append(next) }
            previous = next
            k += 1
            next = cadence.advance(lastCharge, by: k, calendar: calendar)
        }
        return due
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SubscriptionSettlementPlannerTests`
Expected: 7 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/SubscriptionSettlementPlanner.swift Tests/GoldengoCoreTests/SubscriptionSettlementPlannerTests.swift
git commit -m "feat(gol-92): pure due-charge planner for subscription auto-settle"
```

---

### Task 2: `IngestionStore.settleDueSubscriptionCharges` (GoldengoData)

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore.swift` (one-word visibility change on `logEntry`, ~line 257)
- Modify: `Sources/GoldengoData/IngestionStore+Subscriptions.swift` (new public method at the end of the extension)
- Test: Create `Tests/GoldengoDataTests/SettleDueSubscriptionsTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class SettleDueSubscriptionsTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    /// Three monthly Netflix charges (Jan–Mar 5) — enough for the detector's monthly bar.
    /// Pass distinct amounts to make the detector flag the subscription variable-amount.
    private func seedMonthlyNetflix(_ store: IngestionStore, amounts: [Decimal] = [1200, 1200, 1200]) async throws {
        for (i, m) in [1, 2, 3].enumerated() {
            _ = try await store.ingest(NormalizedTransaction(
                externalID: "nf\(i)", amount: amounts[i], currency: .all, date: day(2026, m, 5),
                rawMerchant: "Netflix", kind: .expense, accountRef: "card"), source: .imported)
        }
    }
    private func netflixKey(_ store: IngestionStore) async throws -> String {
        let candidates = try await store.subscriptionCandidates()
        return try XCTUnwrap(candidates.first { $0.displayName.uppercased().contains("NETFLIX") }?.id)
    }

    func test_settle_logsMissedCharges_datedAtDueDates() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        try await store.confirmSubscription(matchKey: try await netflixKey(store))
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 2, "Apr 5 and May 5 fell due (both inside the 60-day horizon)")
        let auto = try await store.recentExpenses(limit: 20).filter { $0.source == .automatic }
        XCTAssertEqual(Set(auto.map(\.date)), [day(2026, 4, 5), day(2026, 5, 5)])
        XCTAssertTrue(auto.allSatisfy { $0.amount == 1200 && $0.currencyCode == "ALL" },
                      "Settled entries carry the subscription's amount and currency")
        XCTAssertTrue(auto.allSatisfy { $0.subscriptionName != nil },
                      "Settled entries are linked to the confirmed subscription")
    }

    func test_settle_isIdempotent() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        try await store.confirmSubscription(matchKey: try await netflixKey(store))
        _ = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        let countAfterFirst = try await store.expenseCount()
        let secondRun = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(secondRun, 0, "The settled entries are now the last observed charges — nothing due")
        let countAfterSecond = try await store.expenseCount()
        XCTAssertEqual(countAfterFirst, countAfterSecond)
    }

    func test_settle_skipsUnconfirmed() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        // Detected but never confirmed → no consent → nothing settled.
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 0)
    }

    func test_settle_skipsDismissed() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        try await store.dismissSubscription(matchKey: try await netflixKey(store))
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 0)
    }

    func test_settle_skipsVariableAmount() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store, amounts: [900, 1200, 1500])
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        try await store.confirmSubscription(matchKey: try await netflixKey(store))
        let created = try await store.settleDueSubscriptionCharges(now: day(2026, 5, 12))
        XCTAssertEqual(created, 0, "Variable-amount subs have no trustworthy amount — never guess")
    }
}
```

**Note on `test_settle_skipsVariableAmount`:** if the detector does NOT flag `[900, 1200, 1500]` as variable (check `SubscriptionDetector`'s variable-amount rule when the test misbehaves — the candidate may be rejected outright instead, which also yields 0 and still proves the guard), adjust the seed amounts to whatever the detector's rule needs (e.g. `[1000, 1200, 1000]`); the assertion stays `created == 0` either way, but verify via `subscriptionCandidates()` that a candidate exists and `isVariableAmount == true`, so the test exercises the intended guard rather than passing vacuously.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettleDueSubscriptionsTests`
Expected: COMPILE FAILURE — `value of type 'IngestionStore' has no member 'settleDueSubscriptionCharges'`

- [ ] **Step 3: Widen `logEntry` visibility**

In `Sources/GoldengoData/IngestionStore.swift` (~line 257), the sweep lives in `IngestionStore+Subscriptions.swift` and `private` is file-scoped, so change exactly one word — `private func logEntry(` → `func logEntry(` (internal, same module only):

```swift
    @discardableResult
    func logEntry(amount: Decimal, currency: CurrencyCode, merchant: String?, note: String?,
                  categoryName: String?, source: ExpenseSource, keyPrefix: String,
                  date: Date = .now, fundedBySourceID: String? = nil) throws -> String {
```

- [ ] **Step 4: Write the sweep**

Append to the extension in `Sources/GoldengoData/IngestionStore+Subscriptions.swift`:

```swift
    /// GOL-92: logs due-but-unlogged charges for confirmed fixed-amount subscriptions as
    /// `.automatic` entries dated at the due date. Idempotent — due dates derive from the most
    /// recent observed charge, and each settled entry becomes the new anchor. `.automatic` is
    /// load-bearing: it's the only source a later statement import reconciles into (GOL-79).
    /// Returns the number of entries created.
    @discardableResult
    public func settleDueSubscriptionCharges(now: Date = .now) throws -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let subs = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
        let expenseRaw = TransactionKind.expense.rawValue
        var created = 0
        var seenKeys = Set<String>()   // CloudKit can briefly hold matchKey duplicates — settle each key once
        for sub in subs where sub.isConfirmed && !sub.isDismissed && !sub.isArchived && !sub.isVariableAmount {
            guard seenKeys.insert(sub.matchKey).inserted else { continue }
            // Most recent observed charge for this merchant+currency. Merchant (and any Decimal)
            // comparisons stay OUT of the #Predicate — normalize in memory after the fetch.
            let currency = sub.currencyCode
            let candidates = try modelContext.fetch(FetchDescriptor<ExpenseRecord>(
                predicate: #Predicate {
                    $0.isArchived == false && $0.kindRaw == expenseRaw && $0.currencyCode == currency
                }))
            guard let last = candidates
                .filter({ MerchantNormalizer.normalize($0.merchantName) == sub.normalizedMerchant })
                .max(by: { $0.date < $1.date }) else { continue }
            for dueDate in SubscriptionSettlementPlanner.dueCharges(
                lastCharge: last.date, cadence: sub.cadence, now: now, calendar: cal) {
                // Copy the last REAL charge's merchant string (not displayName) so MerchantNormalizer
                // matches a future statement row and the import merges instead of duplicating.
                _ = try logEntry(amount: sub.amount, currency: CurrencyCode(sub.currencyCode),
                                 merchant: last.merchantName, note: nil, categoryName: nil,
                                 source: .automatic, keyPrefix: "auto", date: dueDate)
                created += 1
            }
        }
        return created
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SettleDueSubscriptionsTests`
Expected: 5 tests, 0 failures

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoData/IngestionStore.swift Sources/GoldengoData/IngestionStore+Subscriptions.swift Tests/GoldengoDataTests/SettleDueSubscriptionsTests.swift
git commit -m "feat(gol-92): settleDueSubscriptionCharges store sweep"
```

---

### Task 3: Import-reconciliation regression test

**Files:**
- Modify: `Tests/GoldengoDataTests/SettleDueSubscriptionsTests.swift` (append one test)

This validates the spec's central no-duplicate claim end-to-end. It is EXPECTED to pass immediately (the GOL-79 window `[postingDay − 4, postingDay + 1)` already covers entry-at-due-date + posting lag). If it fails, STOP — the spec's dedup assumption is wrong; do not widen the window without surfacing it.

- [ ] **Step 1: Write the test**

```swift
    func test_laterStatementImport_mergesIntoSettledEntry_noDuplicate() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        try await store.confirmSubscription(matchKey: try await netflixKey(store))
        _ = try await store.settleDueSubscriptionCharges(now: day(2026, 4, 7))   // settles Apr 5
        let before = try await store.expenseCount()
        // The bank statement posts the same charge 2 days after the due date.
        let outcome = try await store.ingest(NormalizedTransaction(
            externalID: nil, amount: 1200, currency: .all, date: day(2026, 4, 7),
            rawMerchant: "NETFLIX 4471", kind: .expense, accountRef: "card"), source: .imported)
        XCTAssertEqual(outcome, .merged, "The posting must reconcile into the settled entry")
        let after = try await store.expenseCount()
        XCTAssertEqual(before, after, "Settle + import of the same charge must not double-count")
    }
```

- [ ] **Step 2: Run it**

Run: `swift test --filter SettleDueSubscriptionsTests`
Expected: 6 tests, 0 failures (this one passes without production changes — it pins the integration)

- [ ] **Step 3: Commit**

```bash
git add Tests/GoldengoDataTests/SettleDueSubscriptionsTests.swift
git commit -m "test(gol-92): settled entry absorbs the later statement posting"
```

---

### Task 4: `RootView` wiring + full verification

**Files:**
- Modify: `Sources/GoldengoFeatures/RootView.swift` (two call sites: the cold-launch `.task` ~line 162, and `.onChange(of: scenePhase)` `.active` ~line 176)

No unit test — the wiring is device-verified per spec (same treatment as the Re-entry scenePhase wiring).

- [ ] **Step 1: Add the sweep to the cold-launch `.task`**

```swift
        .task {
            checkReEntry()            // cold-launch re-entry check (onChange(scenePhase) misses the initial .active)
            checkRitual()             // then the daily check-in (Re-entry takes precedence)
            // Quiet books-keeping (GOL-92): settle due subscription charges before the first load
            // so Home wakes already correct. Failure must never block launch — drop to next foreground.
            _ = try? await store.settleDueSubscriptionCharges()
            await recentModel.load()  // Home is the landing tab
        }
```

- [ ] **Step 2: Add the sweep to the `.active` scenePhase branch**

```swift
            case .active:
                checkReEntry()
                checkRitual()
                applyPendingTab()
                // An expense may have been logged via the Quick-Log shortcut while we were
                // backgrounded; reload so it appears on Home without a manual pull-to-refresh.
                // Settle due subscription charges first (GOL-92) so the reload includes them.
                Task {
                    _ = try? await store.settleDueSubscriptionCharges()
                    await recentModel.load()
                }
```

- [ ] **Step 3: Run the FULL test suite**

Run: `swift test`
Expected: 305 tests, 0 failures (292 baseline + 13 from this plan). Any failure or signal is blocking — do not proceed.

- [ ] **Step 4: Simulator build**

Run: `xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath AppProject/.build build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoFeatures/RootView.swift
git commit -m "feat(gol-92): settle due subscription charges on app foreground"
```

---

### After the plan

Per the standard cycle (not plan steps): adversarial multi-agent review of `git diff main...HEAD`, fix confirmed findings, ff-merge to `main`, push, device build + install, move GOL-92 to **To Verify** with a summary comment.
