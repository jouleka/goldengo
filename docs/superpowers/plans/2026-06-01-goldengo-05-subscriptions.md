# Subscription Detection Implementation Plan (GOL-7)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect recurring charges (subscriptions) on-device from the user's expense history, surface them as candidates the user confirms or dismisses, and predict the next charge date — never silently asserting.

**Architecture:** A **pure, dependency-free detection function** lives in `GoldengoCore` (trivially unit-testable per spec §9). `GoldengoData` adds a CloudKit-safe `SubscriptionRecord` model and `@ModelActor` methods that map expenses → occurrences, run the detector, and **upsert candidates by a stable `matchKey` while preserving the user's confirm/dismiss decisions**. `GoldengoFeatures` adds a Subscriptions tab (Model + View) with confirm / "not a subscription" actions. An optional final task adds local pre-charge reminders (pure planner in Core + thin scheduler in Features).

**Tech Stack:** Swift 6 (strict concurrency), SwiftData + CloudKit, SwiftUI, `@Observable`, `UNUserNotificationCenter` (Task 4 only).

**Branch:** `plan-05-subscriptions` (created before execution; do NOT implement on `main`).

**Commit convention (workspace rule):** Do **NOT** add a `Co-Authored-By: Claude` trailer to any commit. Conventional-commit style messages (`feat:`, `test:`, `fix:`) matching the existing history.

**Key spec references (§9):**
- Group by normalized merchant + similar amount; detect steady interval with **explicit tolerance bands** (weekly 7±2d, monthly 28–31d, quarterly 88–93d, yearly 360–370d) to avoid monthly-vs-4-weekly aliasing.
- Default threshold **≥3 occurrences**, but **yearly uses ≥2**.
- **Free-trial handling:** first charge 0 or off-amount must not discard the series.
- **Variable amounts** (utilities) via an amount-tolerance flag on the candidate.
- Occurrence counting uses **merged** records (already merged at ingest, §6).
- **Surface candidates for the user to confirm — never silently assert.** Confirmed → auto-match future, predict `nextChargeDate`, optional reminder. User can mark "not a subscription" (`dismissed`).

---

## Design Decisions (locked for this plan)

1. **Grouping is merchant-primary + per-currency**, with amount used as a *flag* (`isVariableAmount`) rather than to split groups. This is what makes free-trial (amount 0) and utility (variable amount) series survive grouping (spec §9 lines 100–101). Strict amount sub-clustering (two distinct subscriptions at the same merchant) is a documented future enhancement, out of scope here.
2. **Same calendar day (UTC) collapses to one occurrence** within a merchant+currency group — a subscription bills once per period, so two same-day charges are not two occurrences.
3. **Cadence is classified from the *median* consecutive gap**, and we additionally require that at least half the gaps fall within the chosen band (rejects wildly irregular series). Intervals that match no named band → not surfaced.
4. **`matchKey` = `"<normalizedMerchant>|<cadence.rawValue>|<currencyCode>"`** is the stable identity shared between the pure `SubscriptionCandidate.id` and the persisted `SubscriptionRecord.matchKey`. Re-detection upserts on this key and never overwrites `isConfirmed` / `isDismissed`.
5. **Detection is read-only over expense-kind records** (subscriptions are outflows). Amounts are taken as positive magnitudes.
6. All date math uses a fixed `Calendar(identifier: .gregorian)` with `TimeZone(identifier: "UTC")`, matching the rest of the app.

---

## File Structure

**Create:**
- `Sources/GoldengoCore/SubscriptionTypes.swift` — `SubscriptionCadence`, `TransactionOccurrence`, `SubscriptionCandidate`.
- `Sources/GoldengoCore/SubscriptionDetector.swift` — the pure `detect` function + helpers.
- `Tests/GoldengoCoreTests/SubscriptionDetectorTests.swift` — fixtures (monthly, weekly, yearly≥2, trial, variable, aliasing, irregular, multi-currency).
- `Sources/GoldengoData/Models/SubscriptionRecord.swift` — CloudKit-safe `@Model`.
- `Sources/GoldengoData/IngestionStore+Subscriptions.swift` — `SubscriptionSnapshot`, `refreshSubscriptions`, `subscriptionCandidates`, `confirmSubscription`, `dismissSubscription`.
- `Tests/GoldengoDataTests/SubscriptionStoreTests.swift` — in-memory container integration tests.
- `Sources/GoldengoFeatures/Subscriptions/SubscriptionsModel.swift` — `@Observable @MainActor` model.
- `Sources/GoldengoFeatures/Subscriptions/SubscriptionsView.swift` — list + confirm/dismiss UI.
- (Task 4, optional) `Sources/GoldengoCore/SubscriptionReminderPlanner.swift` + `Tests/GoldengoCoreTests/SubscriptionReminderPlannerTests.swift` + `Sources/GoldengoFeatures/Subscriptions/LocalNotificationScheduler.swift`.

**Modify:**
- `Sources/GoldengoData/ModelContainer+Goldengo.swift` — register `SubscriptionRecord` in the schema.
- `Sources/GoldengoFeatures/RootView.swift` — add Subscriptions tab (tag 4) + `goldengo://subscriptions` deep link.
- `Tests/GoldengoFeaturesTests/...` — extend the existing deep-link routing test for `subscriptions`.

---

## Task 1: Core detection engine (pure, `GoldengoCore`)

**Files:**
- Create: `Sources/GoldengoCore/SubscriptionTypes.swift`
- Create: `Sources/GoldengoCore/SubscriptionDetector.swift`
- Test: `Tests/GoldengoCoreTests/SubscriptionDetectorTests.swift`

- [ ] **Step 1: Write the types**

Create `Sources/GoldengoCore/SubscriptionTypes.swift`:

```swift
import Foundation

/// Billing cadence with explicit day-tolerance bands to avoid monthly-vs-4-weekly aliasing (spec §9).
public enum SubscriptionCadence: String, Sendable, CaseIterable, Codable {
    case weekly, monthly, quarterly, yearly

    /// Inclusive day-gap band a consecutive interval must fall in to count as this cadence.
    public var dayBand: ClosedRange<Int> {
        switch self {
        case .weekly:    return 5...9      // 7 ± 2
        case .monthly:   return 28...31
        case .quarterly: return 88...93
        case .yearly:    return 360...370
        }
    }

    /// Minimum occurrences required to surface a candidate at this cadence.
    /// Long cadences relax the bar — 3 yearly charges would take ~3 years (spec §9).
    public var minimumOccurrences: Int { self == .yearly ? 2 : 3 }

    /// Advance a date by exactly one period of this cadence (calendar-accurate, not 30-day approx).
    public func advance(_ date: Date, by periods: Int = 1, calendar: Calendar) -> Date {
        var comps = DateComponents()
        switch self {
        case .weekly:    comps.day = 7 * periods
        case .monthly:   comps.month = periods
        case .quarterly: comps.month = 3 * periods
        case .yearly:    comps.year = periods
        }
        return calendar.date(byAdding: comps, to: date) ?? date
    }
}

/// A normalized, `Sendable` occurrence the detector reasons over. The persistence layer maps
/// its records into these; the detector stays pure and dependency-free.
public struct TransactionOccurrence: Hashable, Sendable {
    public var id: String          // stable record key (e.g. dedupeKey) for traceability
    public var date: Date
    public var amount: Decimal     // positive magnitude
    public var currency: CurrencyCode
    public var merchant: String?   // raw; detector normalizes via MerchantNormalizer

    public init(id: String, date: Date, amount: Decimal, currency: CurrencyCode, merchant: String?) {
        self.id = id; self.date = date; self.amount = amount
        self.currency = currency; self.merchant = merchant
    }
}

/// A detected recurring-charge candidate. Never asserted — surfaced for user confirmation (spec §9).
public struct SubscriptionCandidate: Hashable, Sendable, Identifiable {
    public var id: String              // matchKey: "<normalizedMerchant>|<cadence>|<currency>"
    public var displayName: String     // most recent non-empty raw merchant
    public var normalizedMerchant: String
    public var amount: Decimal         // representative (median) positive magnitude
    public var currency: CurrencyCode
    public var cadence: SubscriptionCadence
    public var occurrenceCount: Int
    public var firstCharge: Date
    public var lastCharge: Date
    public var predictedNextCharge: Date
    public var isVariableAmount: Bool  // utilities etc.
    public var hadTrial: Bool          // first charge 0 / off-amount
    public var confidence: Double      // 0...1, interval regularity × occurrence weight
    public var memberIDs: [String]     // occurrence ids that formed this series

    public init(id: String, displayName: String, normalizedMerchant: String, amount: Decimal,
                currency: CurrencyCode, cadence: SubscriptionCadence, occurrenceCount: Int,
                firstCharge: Date, lastCharge: Date, predictedNextCharge: Date,
                isVariableAmount: Bool, hadTrial: Bool, confidence: Double, memberIDs: [String]) {
        self.id = id; self.displayName = displayName; self.normalizedMerchant = normalizedMerchant
        self.amount = amount; self.currency = currency; self.cadence = cadence
        self.occurrenceCount = occurrenceCount; self.firstCharge = firstCharge
        self.lastCharge = lastCharge; self.predictedNextCharge = predictedNextCharge
        self.isVariableAmount = isVariableAmount; self.hadTrial = hadTrial
        self.confidence = confidence; self.memberIDs = memberIDs
    }
}
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/GoldengoCoreTests/SubscriptionDetectorTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class SubscriptionDetectorTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func occ(_ id: String, _ date: Date, _ amount: Double, _ merchant: String, _ cur: CurrencyCode = .all) -> TransactionOccurrence {
        TransactionOccurrence(id: id, date: date, amount: Decimal(amount), currency: cur, merchant: merchant)
    }

    func test_detectsMonthlySubscription_threeOccurrences() {
        let occs = [
            occ("1", day(2026, 1, 5), 9.99, "Netflix"),
            occ("2", day(2026, 2, 5), 9.99, "NETFLIX 4471"),   // numeric token dropped by normalizer
            occ("3", day(2026, 3, 5), 9.99, "Netflix"),
        ]
        let result = SubscriptionDetector.detect(occs, options: .init(now: day(2026, 3, 10)))
        XCTAssertEqual(result.count, 1)
        let c = result[0]
        XCTAssertEqual(c.cadence, .monthly)
        XCTAssertEqual(c.occurrenceCount, 3)
        XCTAssertEqual(c.amount, Decimal(9.99))
        XCTAssertEqual(c.normalizedMerchant, "NETFLIX")
        XCTAssertFalse(c.isVariableAmount)
        XCTAssertFalse(c.hadTrial)
        // predicted next charge after last (Mar 5) → Apr 5
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: c.predictedNextCharge),
                       cal.dateComponents([.year, .month, .day], from: day(2026, 4, 5)))
        XCTAssertGreaterThan(c.confidence, 0.7)
    }

    func test_twoMonthlyChargesAreNotEnough() {
        let occs = [occ("1", day(2026, 1, 5), 9.99, "Spotify"),
                    occ("2", day(2026, 2, 5), 9.99, "Spotify")]
        XCTAssertTrue(SubscriptionDetector.detect(occs, options: .init(now: day(2026, 2, 10))).isEmpty)
    }

    func test_detectsYearlyWithTwoOccurrences() {
        let occs = [occ("1", day(2024, 6, 1), 99.0, "iCloud+"),
                    occ("2", day(2025, 6, 2), 99.0, "iCloud+")]
        let result = SubscriptionDetector.detect(occs, options: .init(now: day(2025, 7, 1)))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].cadence, .yearly)
        XCTAssertEqual(result[0].occurrenceCount, 2)
    }

    func test_detectsWeeklyAndPredictsForward_pastLastCharge() {
        // Weekly series ends well before `now`; predicted next must roll forward to be > now.
        let base = day(2026, 1, 1)
        let occs = (0..<4).map { i in occ("\(i)", cal.date(byAdding: .day, value: 7*i, to: base)!, 4.0, "Gym Locker") }
        let now = day(2026, 3, 1)
        let result = SubscriptionDetector.detect(occs, options: .init(now: now))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].cadence, .weekly)
        XCTAssertGreaterThan(result[0].predictedNextCharge, now)
    }

    func test_freeTrialThenPaid_isOneSeriesWithTrialFlag() {
        let occs = [
            occ("0", day(2026, 1, 10), 0.0, "Disney Plus"),     // trial
            occ("1", day(2026, 2, 10), 7.99, "Disney Plus"),
            occ("2", day(2026, 3, 10), 7.99, "Disney Plus"),
            occ("3", day(2026, 4, 10), 7.99, "Disney Plus"),
        ]
        let result = SubscriptionDetector.detect(occs, options: .init(now: day(2026, 4, 15)))
        XCTAssertEqual(result.count, 1)
        let c = result[0]
        XCTAssertEqual(c.cadence, .monthly)
        XCTAssertTrue(c.hadTrial)
        XCTAssertEqual(c.amount, Decimal(7.99))   // representative excludes the 0 trial
        XCTAssertEqual(c.occurrenceCount, 4)
    }

    func test_variableAmountUtility_flagged() {
        let occs = [
            occ("1", day(2026, 1, 15), 40.0, "Elektrik OSHEE"),
            occ("2", day(2026, 2, 15), 55.0, "Elektrik OSHEE"),
            occ("3", day(2026, 3, 15), 48.0, "Elektrik OSHEE"),
        ]
        let result = SubscriptionDetector.detect(occs, options: .init(now: day(2026, 3, 20)))
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isVariableAmount)
        XCTAssertEqual(result[0].cadence, .monthly)
    }

    func test_irregularIntervals_notDetected() {
        let occs = [
            occ("1", day(2026, 1, 1), 5.0, "Random Cafe"),
            occ("2", day(2026, 1, 3), 5.0, "Random Cafe"),
            occ("3", day(2026, 2, 20), 5.0, "Random Cafe"),
        ]
        XCTAssertTrue(SubscriptionDetector.detect(occs, options: .init(now: day(2026, 3, 1))).isEmpty)
    }

    func test_sameDayChargesCollapseToOneOccurrence() {
        // Two charges the same day must not count as two occurrences.
        let occs = [
            occ("1", day(2026, 1, 5), 9.99, "Netflix"),
            occ("1b", day(2026, 1, 5), 9.99, "Netflix"),
            occ("2", day(2026, 2, 5), 9.99, "Netflix"),
        ]
        // Only 2 distinct days → below monthly threshold of 3 → not detected.
        XCTAssertTrue(SubscriptionDetector.detect(occs, options: .init(now: day(2026, 2, 10))).isEmpty)
    }

    func test_differentCurrenciesDoNotMerge() {
        let occs = [
            occ("1", day(2026, 1, 5), 9.99, "Netflix", .all),
            occ("2", day(2026, 2, 5), 9.99, "Netflix", .all),
            occ("3", day(2026, 3, 5), 9.99, "Netflix", .all),
            occ("4", day(2026, 1, 5), 5.0, "Netflix", CurrencyCode("USD")),
            occ("5", day(2026, 2, 5), 5.0, "Netflix", CurrencyCode("USD")),
            occ("6", day(2026, 3, 5), 5.0, "Netflix", CurrencyCode("USD")),
        ]
        let result = SubscriptionDetector.detect(occs, options: .init(now: day(2026, 3, 10)))
        XCTAssertEqual(result.count, 2)   // one per currency
        XCTAssertEqual(Set(result.map(\.currency.rawValue)), ["ALL", "USD"])
    }

    func test_emptyAndUnknownMerchant_ignored() {
        let occs = [
            occ("1", day(2026, 1, 5), 9.99, "   "),
            occ("2", day(2026, 2, 5), 9.99, "4471"),   // all-numeric → normalizes to ""
        ]
        XCTAssertTrue(SubscriptionDetector.detect(occs, options: .init(now: day(2026, 3, 1))).isEmpty)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter GoldengoCoreTests.SubscriptionDetectorTests`
Expected: FAIL — `SubscriptionDetector` not defined / no `detect`.

- [ ] **Step 4: Write the detector**

Create `Sources/GoldengoCore/SubscriptionDetector.swift`:

```swift
import Foundation

/// Pure, on-device subscription detection (spec §9). Operates over `TransactionOccurrence`
/// value types so it has zero persistence/UI dependencies and is trivially unit-testable.
public enum SubscriptionDetector {

    public struct Options: Sendable {
        /// Relative amount-spread threshold for the `isVariableAmount` flag (spec §9 "amount-tolerance
        /// flag"): when the in-series amounts span more than this fraction of the median, the candidate
        /// is flagged variable (utilities etc.). A normal price change below this stays "fixed".
        public var amountTolerance: Double
        /// "Now", used to roll the predicted next charge forward past the last observed charge.
        public var now: Date
        public init(amountTolerance: Double = 0.15, now: Date = .now) {
            self.amountTolerance = amountTolerance; self.now = now
        }
    }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    public static func detect(_ occurrences: [TransactionOccurrence], options: Options = .init()) -> [SubscriptionCandidate] {
        // Group by normalized merchant + currency. Drop occurrences that normalize to "".
        var groups: [String: [TransactionOccurrence]] = [:]
        for o in occurrences {
            let norm = MerchantNormalizer.normalize(o.merchant)
            guard !norm.isEmpty else { continue }
            groups["\(norm)|\(o.currency.rawValue)", default: []].append(o)
        }

        var candidates: [SubscriptionCandidate] = []
        for (_, raw) in groups {
            guard let c = candidate(from: raw, options: options) else { continue }
            candidates.append(c)
        }
        // Stable, useful order: most confident first.
        return candidates.sorted { $0.confidence > $1.confidence }
    }

    private static func candidate(from raw: [TransactionOccurrence], options: Options) -> SubscriptionCandidate? {
        let norm = MerchantNormalizer.normalize(raw.first?.merchant)
        guard !norm.isEmpty else { return nil }
        let currency = raw.first!.currency

        // Collapse same UTC day to one occurrence (keep the larger amount).
        var byDay: [Date: TransactionOccurrence] = [:]
        for o in raw {
            let d = calendar.startOfDay(for: o.date)
            if let existing = byDay[d] { if o.amount > existing.amount { byDay[d] = o } }
            else { byDay[d] = o }
        }
        let series = byDay.values.sorted { $0.date < $1.date }
        guard series.count >= 2 else { return nil }

        // Consecutive day gaps.
        var gaps: [Int] = []
        for i in 1..<series.count {
            let g = calendar.dateComponents([.day], from: series[i - 1].date, to: series[i].date).day ?? 0
            gaps.append(g)
        }
        let sortedGaps = gaps.sorted()
        let medianGap = sortedGaps[sortedGaps.count / 2]

        // Classify cadence by the median gap; require a band match.
        guard let cadence = SubscriptionCadence.allCases.first(where: { $0.dayBand.contains(medianGap) }) else { return nil }
        // Reject wildly irregular series: at least half the gaps must be in-band.
        let inBand = gaps.filter { cadence.dayBand.contains($0) }.count
        guard inBand >= max(1, gaps.count / 2) else { return nil }
        // Occurrence threshold (yearly relaxes to 2).
        guard series.count >= cadence.minimumOccurrences else { return nil }

        // Amounts: representative = median of positive amounts; trial = any 0 amount.
        let positive = series.map(\.amount).filter { $0 > 0 }.sorted()
        guard !positive.isEmpty else { return nil }
        let median = positive[positive.count / 2]
        let hadTrial = series.contains { $0.amount == 0 }
        // Variable-amount flag: compute the spread ratio in Double (avoids Decimal(Double) literal
        // imprecision) and compare against the public tolerance knob (default 15%).
        let spread = positive.last! - positive.first!
        let ratio = median > 0
            ? NSDecimalNumber(decimal: spread).doubleValue / NSDecimalNumber(decimal: median).doubleValue
            : 0
        let isVariableAmount = ratio > options.amountTolerance

        // Predicted next charge: advance one period past the last charge, rolling forward past `now`.
        var next = cadence.advance(series.last!.date, calendar: calendar)
        while next < options.now { next = cadence.advance(next, calendar: calendar) }

        // Confidence: interval regularity (low coefficient of variation) weighted with occurrence count.
        let gd = gaps.map(Double.init)
        let mean = gd.reduce(0, +) / Double(gd.count)
        let variance = gd.reduce(0) { $0 + pow($1 - mean, 2) } / Double(gd.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 1
        let regularity = max(0, 1 - cv)
        let occWeight = min(1.0, Double(series.count) / 6.0)
        let confidence = min(1, max(0, 0.6 * regularity + 0.4 * occWeight))

        // Display name: most recent non-empty raw merchant.
        let displayName = series.reversed().compactMap { $0.merchant?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? norm

        return SubscriptionCandidate(
            id: "\(norm)|\(cadence.rawValue)|\(currency.rawValue)",
            displayName: displayName, normalizedMerchant: norm, amount: median, currency: currency,
            cadence: cadence, occurrenceCount: series.count,
            firstCharge: series.first!.date, lastCharge: series.last!.date,
            predictedNextCharge: next, isVariableAmount: isVariableAmount, hadTrial: hadTrial,
            confidence: confidence, memberIDs: series.map(\.id))
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter GoldengoCoreTests.SubscriptionDetectorTests`
Expected: PASS (all cases). The variable-amount check computes its ratio in `Double` against `options.amountTolerance` (15%), so there is no `Decimal(Double)` precision pitfall: the utility fixture (spread 15/median 48 ≈ 0.31 > 0.15) flags variable; the fixed 9.99/7.99 series (spread 0) do not.

- [ ] **Step 6: Run the full Core suite (no regressions)**

Run: `swift test --filter GoldengoCoreTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/GoldengoCore/SubscriptionTypes.swift Sources/GoldengoCore/SubscriptionDetector.swift Tests/GoldengoCoreTests/SubscriptionDetectorTests.swift
git commit -m "feat: pure on-device subscription detector (cadence bands, trials, variable amounts)"
```

---

## Task 2: Persistence — `SubscriptionRecord` + store methods (`GoldengoData`)

**Files:**
- Create: `Sources/GoldengoData/Models/SubscriptionRecord.swift`
- Create: `Sources/GoldengoData/IngestionStore+Subscriptions.swift`
- Modify: `Sources/GoldengoData/ModelContainer+Goldengo.swift` (register the model in the schema)
- Test: `Tests/GoldengoDataTests/SubscriptionStoreTests.swift`

> **Context for the implementer:** `IngestionStore` is an `@ModelActor` (see `Sources/GoldengoData/IngestionStore.swift`). Expenses are `ExpenseRecord` (`amount: Decimal`, `currencyCode: String`, `date`, `merchantName: String?`, `kindRaw`, `dedupeKey`, `isArchived`). Use `kindRaw == TransactionKind.expense.rawValue` and `isArchived == false`. CloudKit rules: every stored property needs a default value, **no** `@Attribute(.unique)`, relationships optional. Map each expense to `TransactionOccurrence(id: dedupeKey, date:, amount: <positive>, currency: CurrencyCode(currencyCode), merchant: merchantName)`.

- [ ] **Step 1: Write the model**

Create `Sources/GoldengoData/Models/SubscriptionRecord.swift`:

```swift
import Foundation
import SwiftData
import GoldengoCore

@Model
public final class SubscriptionRecord {
    public var matchKey: String = ""               // "<normalizedMerchant>|<cadence>|<currency>"
    public var displayName: String = ""
    public var normalizedMerchant: String = ""
    public var amount: Decimal = 0
    public var currencyCode: String = "ALL"
    public var cadenceRaw: String = SubscriptionCadence.monthly.rawValue
    public var nextChargeDate: Date = Date.now
    public var occurrenceCount: Int = 0
    public var confidence: Double = 0
    public var isVariableAmount: Bool = false
    public var hadTrial: Bool = false
    public var isConfirmed: Bool = false           // user said "yes, it's a subscription"
    public var isDismissed: Bool = false           // user said "not a subscription"
    public var isArchived: Bool = false            // tombstone (CloudKit-friendly)
    public var detectedAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public init(matchKey: String = "", displayName: String = "", normalizedMerchant: String = "",
                amount: Decimal = 0, currencyCode: String = "ALL",
                cadence: SubscriptionCadence = .monthly, nextChargeDate: Date = .now,
                occurrenceCount: Int = 0, confidence: Double = 0,
                isVariableAmount: Bool = false, hadTrial: Bool = false) {
        self.matchKey = matchKey; self.displayName = displayName
        self.normalizedMerchant = normalizedMerchant; self.amount = amount
        self.currencyCode = currencyCode; self.cadenceRaw = cadence.rawValue
        self.nextChargeDate = nextChargeDate; self.occurrenceCount = occurrenceCount
        self.confidence = confidence; self.isVariableAmount = isVariableAmount; self.hadTrial = hadTrial
    }

    public var cadence: SubscriptionCadence { SubscriptionCadence(rawValue: cadenceRaw) ?? .monthly }
}
```

- [ ] **Step 2: Register the model in the schema**

Open `Sources/GoldengoData/ModelContainer+Goldengo.swift`. Find the `Schema([...])` array listing the `@Model` types (e.g. `ExpenseRecord.self, CategoryRecord.self, ...`). Add `SubscriptionRecord.self` to that array. (If the schema is built elsewhere, add it wherever the other models are registered.)

- [ ] **Step 3: Write the failing tests**

Create `Tests/GoldengoDataTests/SubscriptionStoreTests.swift`:

```swift
import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class SubscriptionStoreTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    private func makeStore() throws -> IngestionStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ExpenseRecord.self, CategoryRecord.self, AccountRecord.self,
                                           MerchantRecord.self, ImportBatch.self, SubscriptionRecord.self,
                                           configurations: config)
        return IngestionStore(modelContainer: container)
    }

    private func seedMonthlyNetflix(_ store: IngestionStore) async throws {
        for (i, m) in [1, 2, 3].enumerated() {
            _ = try await store.ingest(
                NormalizedTransaction(externalID: "nf\(i)", amount: Decimal(9.99), currency: .all,
                                      date: day(2026, m, 5), rawMerchant: "Netflix",
                                      kind: .expense, accountRef: "card"), source: .imported)
        }
    }

    func test_refreshCreatesCandidate() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        let count = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        XCTAssertEqual(count, 1)
        let cands = try await store.subscriptionCandidates()
        XCTAssertEqual(cands.count, 1)
        XCTAssertEqual(cands[0].cadence, .monthly)
        XCTAssertEqual(cands[0].displayName, "Netflix")
    }

    func test_confirmIsPreservedAcrossRefresh() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        let key = try await store.subscriptionCandidates()[0].id
        try await store.confirmSubscription(matchKey: key)
        // Re-running detection must not reset the user's decision.
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 11))
        let after = try await store.subscriptionCandidates().first { $0.id == key }
        XCTAssertEqual(after?.isConfirmed, true)
    }

    func test_dismissedCandidatesAreNotResurfaced() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        let key = try await store.subscriptionCandidates()[0].id
        try await store.dismissSubscription(matchKey: key)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 11))
        let cands = try await store.subscriptionCandidates()   // excludes dismissed
        XCTAssertTrue(cands.isEmpty)
    }

    func test_refreshIsIdempotent_noDuplicateRecords() async throws {
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 11))
        XCTAssertEqual(try await store.subscriptionRecordCount(), 1)
    }

    func test_duplicateMatchKeysConvergeOnRefresh_noCrash() async throws {
        // Simulate a CloudKit cross-device duplicate: two SubscriptionRecords share a matchKey.
        // refreshSubscriptions must NOT trap and must converge to a single active candidate.
        let store = try makeStore()
        try await seedMonthlyNetflix(store)
        _ = try await store.refreshSubscriptions(now: day(2026, 3, 10))
        let key = try await store.subscriptionCandidates()[0].id

        let ctx = ModelContext(store.modelContainer)   // @ModelActor exposes nonisolated modelContainer
        ctx.insert(SubscriptionRecord(matchKey: key, displayName: "Netflix dup", cadence: .monthly))
        try ctx.save()
        XCTAssertEqual(try await store.subscriptionRecordCount(), 2)

        _ = try await store.refreshSubscriptions(now: day(2026, 3, 11))   // must not crash
        let active = try await store.subscriptionCandidates().filter { $0.id == key }
        XCTAssertEqual(active.count, 1)   // converged: one archived, one active
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift test --filter GoldengoDataTests.SubscriptionStoreTests`
Expected: FAIL — methods not defined.

- [ ] **Step 5: Write the store methods**

Create `Sources/GoldengoData/IngestionStore+Subscriptions.swift`:

```swift
import Foundation
import SwiftData
import GoldengoCore

/// `Sendable` view of a detected/persisted subscription, safe to cross the actor boundary to the UI.
public struct SubscriptionSnapshot: Sendable, Equatable, Identifiable {
    public var id: String              // matchKey
    public var displayName: String
    public var amount: Decimal
    public var currencyCode: String
    public var cadence: SubscriptionCadence
    public var nextChargeDate: Date
    public var occurrenceCount: Int
    public var confidence: Double
    public var isVariableAmount: Bool
    public var hadTrial: Bool
    public var isConfirmed: Bool
}

extension IngestionStore {
    /// Run detection over all non-archived expense-kind records and UPSERT candidates by `matchKey`,
    /// preserving the user's confirm/dismiss decisions. Returns the count of surfaced (non-dismissed)
    /// candidates.
    @discardableResult
    public func refreshSubscriptions(now: Date = .now) throws -> Int {
        let expenseRaw = TransactionKind.expense.rawValue
        let fd = FetchDescriptor<ExpenseRecord>(predicate: #Predicate {
            $0.isArchived == false && $0.kindRaw == expenseRaw
        })
        let occurrences = try modelContext.fetch(fd).map { r in
            TransactionOccurrence(id: r.dedupeKey, date: r.date, amount: abs(r.amount),
                                  currency: CurrencyCode(r.currencyCode), merchant: r.merchantName)
        }
        let detected = SubscriptionDetector.detect(occurrences, options: .init(now: now))

        // Build the lookup defensively: `matchKey` is NOT unique (CloudKit cross-device inserts can
        // produce two rows with the same key). `Dictionary(uniqueKeysWithValues:)` would TRAP on that.
        // Converge duplicates here — keep the row carrying a user decision, archive the loser.
        let existingAll = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>())
        var byKey: [String: SubscriptionRecord] = [:]
        for r in existingAll {
            guard let kept = byKey[r.matchKey] else { byKey[r.matchKey] = r; continue }
            let rHasDecision = r.isConfirmed || r.isDismissed
            let keptHasDecision = kept.isConfirmed || kept.isDismissed
            let winner = (rHasDecision && !keptHasDecision) ? r : kept
            let loser = (winner === r) ? kept : r
            loser.isArchived = true
            byKey[r.matchKey] = winner
        }

        for c in detected {
            if let rec = byKey[c.id] {
                // Update detection-derived fields; NEVER touch isConfirmed / isDismissed.
                rec.displayName = c.displayName
                rec.amount = c.amount
                rec.cadenceRaw = c.cadence.rawValue
                rec.nextChargeDate = c.predictedNextCharge
                rec.occurrenceCount = c.occurrenceCount
                rec.confidence = c.confidence
                rec.isVariableAmount = c.isVariableAmount
                rec.hadTrial = c.hadTrial
                rec.isArchived = false
                rec.updatedAt = now
            } else {
                let rec = SubscriptionRecord(
                    matchKey: c.id, displayName: c.displayName, normalizedMerchant: c.normalizedMerchant,
                    amount: c.amount, currencyCode: c.currency.rawValue, cadence: c.cadence,
                    nextChargeDate: c.predictedNextCharge, occurrenceCount: c.occurrenceCount,
                    confidence: c.confidence, isVariableAmount: c.isVariableAmount, hadTrial: c.hadTrial)
                rec.detectedAt = now; rec.updatedAt = now
                modelContext.insert(rec)
                byKey[c.id] = rec
            }
        }
        try modelContext.save()

        let detectedKeys = Set(detected.map(\.id))
        return byKey.values.filter { !$0.isDismissed && !$0.isArchived && detectedKeys.contains($0.matchKey) }.count
    }

    /// Candidates to show the user: currently-detected, not dismissed, not archived, most confident first.
    /// `includeConfirmed` keeps already-confirmed ones in the list (so the user can review/undo).
    public func subscriptionCandidates(includeConfirmed: Bool = true) throws -> [SubscriptionSnapshot] {
        let recs = try modelContext.fetch(FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate { $0.isArchived == false && $0.isDismissed == false }))
        return recs
            .filter { includeConfirmed || !$0.isConfirmed }
            .sorted { $0.confidence > $1.confidence }
            .map { SubscriptionSnapshot(
                id: $0.matchKey, displayName: $0.displayName, amount: $0.amount,
                currencyCode: $0.currencyCode, cadence: $0.cadence, nextChargeDate: $0.nextChargeDate,
                occurrenceCount: $0.occurrenceCount, confidence: $0.confidence,
                isVariableAmount: $0.isVariableAmount, hadTrial: $0.hadTrial, isConfirmed: $0.isConfirmed) }
    }

    public func confirmSubscription(matchKey: String) throws {
        guard let rec = try fetchSubscription(matchKey: matchKey) else { return }
        rec.isConfirmed = true; rec.isDismissed = false; rec.updatedAt = .now
        try modelContext.save()
    }

    public func dismissSubscription(matchKey: String) throws {
        guard let rec = try fetchSubscription(matchKey: matchKey) else { return }
        rec.isDismissed = true; rec.isConfirmed = false; rec.updatedAt = .now
        try modelContext.save()
    }

    public func subscriptionRecordCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<SubscriptionRecord>())
    }

    private func fetchSubscription(matchKey key: String) throws -> SubscriptionRecord? {
        var fd = FetchDescriptor<SubscriptionRecord>(predicate: #Predicate { $0.matchKey == key })
        fd.fetchLimit = 1
        return try modelContext.fetch(fd).first
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter GoldengoDataTests.SubscriptionStoreTests`
Expected: PASS.

- [ ] **Step 7: Run the full Data suite (no regressions)**

Run: `swift test --filter GoldengoDataTests`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/GoldengoData/Models/SubscriptionRecord.swift Sources/GoldengoData/IngestionStore+Subscriptions.swift Sources/GoldengoData/ModelContainer+Goldengo.swift Tests/GoldengoDataTests/SubscriptionStoreTests.swift
git commit -m "feat: persist subscription candidates with confirm/dismiss preserved across re-detection"
```

---

## Task 3: Subscriptions feature UI (`GoldengoFeatures`)

**Files:**
- Create: `Sources/GoldengoFeatures/Subscriptions/SubscriptionsModel.swift`
- Create: `Sources/GoldengoFeatures/Subscriptions/SubscriptionsView.swift`
- Modify: `Sources/GoldengoFeatures/RootView.swift` (add tab tag 4 + deep link)
- Test: extend the existing deep-link routing test in `Tests/GoldengoFeaturesTests/`

> **Context for the implementer:** Mirror the existing feature pattern in `Sources/GoldengoFeatures/Recent/` — `@MainActor @Observable` model exposing `public private(set)` state and `async` methods that call the `IngestionStore`; the View uses `@State private var model`, `init(model:)`, `NavigationStack { List { ... } }`, `ContentUnavailableView` for the empty state, and `.onAppear { Task { await model.load() } }`. Use `GoldengoDesignSystem` and the `Money` formatter from `GoldengoCore`.

- [ ] **Step 1: Write the model**

Create `Sources/GoldengoFeatures/Subscriptions/SubscriptionsModel.swift`:

```swift
import Foundation
import Observation
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class SubscriptionsModel {
    public let store: IngestionStore
    public private(set) var rows: [SubscriptionSnapshot] = []
    public private(set) var isLoading = false

    public init(store: IngestionStore) { self.store = store }

    /// Re-run detection, then load the surfaced candidates.
    public func load() async {
        isLoading = true
        _ = try? await store.refreshSubscriptions()
        rows = (try? await store.subscriptionCandidates()) ?? []
        isLoading = false
    }

    public func confirm(_ s: SubscriptionSnapshot) async {
        try? await store.confirmSubscription(matchKey: s.id)
        await load()
    }

    public func dismiss(_ s: SubscriptionSnapshot) async {
        try? await store.dismissSubscription(matchKey: s.id)
        await load()
    }

    /// "L 9.99 / month" style label.
    public func amountCadenceText(_ s: SubscriptionSnapshot) -> String {
        let money = Money(amount: s.amount, currency: CurrencyCode(s.currencyCode)).formatted()
        let per: String
        switch s.cadence {
        case .weekly: per = "week"; case .monthly: per = "month"
        case .quarterly: per = "quarter"; case .yearly: per = "year"
        }
        return "\(money) / \(per)"
    }

    public func nextChargeText(_ s: SubscriptionSnapshot) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return "Next: \(f.string(from: s.nextChargeDate))"
    }
}
```

- [ ] **Step 2: Write the view**

Create `Sources/GoldengoFeatures/Subscriptions/SubscriptionsView.swift`:

```swift
import SwiftUI
import GoldengoCore
import GoldengoData
import GoldengoDesignSystem

public struct SubscriptionsView: View {
    @State private var model: SubscriptionsModel
    public init(model: SubscriptionsModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            List {
                if model.rows.isEmpty {
                    if #available(iOS 17.0, *) {
                        ContentUnavailableView(
                            "No subscriptions detected",
                            systemImage: "repeat.circle",
                            description: Text("Import statements or log expenses, then pull to refresh."))
                    } else {
                        Text("No subscriptions detected yet.").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.rows) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(s.displayName).font(.headline)
                                if s.isConfirmed {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                }
                                Spacer()
                                Text(model.amountCadenceText(s)).font(.subheadline.bold())
                            }
                            Text(model.nextChargeText(s)).font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text("\(s.occurrenceCount)×").font(.caption2)
                                if s.hadTrial { Label("trial", systemImage: "gift").font(.caption2) }
                                if s.isVariableAmount { Label("variable", systemImage: "waveform").font(.caption2) }
                                Spacer()
                                Text("\(Int((s.confidence * 100).rounded()))%").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Not a subscription", role: .destructive) { Task { await model.dismiss(s) } }
                            if !s.isConfirmed {
                                Button("Confirm") { Task { await model.confirm(s) } }.tint(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Subscriptions")
            .refreshable { await model.load() }
            .onAppear { Task { await model.load() } }
        }
    }
}
```

- [ ] **Step 3: Add the tab + deep link to RootView**

In `Sources/GoldengoFeatures/RootView.swift`:

1. Add a tab inside the `TabView`. **`TabView` renders in declaration order, not tag order**, so insert this block **immediately after the Import tab and before the `SettingsView` tab** to keep Settings visually last. Use tag 4 (tags must stay unique; 0/1/2/3 are taken):

```swift
            SubscriptionsView(model: SubscriptionsModel(store: store))
                .tabItem { Label("Subs", systemImage: "repeat.circle") }
                .tag(4)
```

2. Extend `tab(forDeepLink:)` with:

```swift
        case "subscriptions": return 4
```

- [ ] **Step 4: Extend the deep-link routing test**

Find the existing routing test in `Tests/GoldengoFeaturesTests/` (it covers `goldengo://settings`, `quickadd`, `recent`, `import`). Add a case asserting `subscriptions` maps to 4:

```swift
    func test_deepLink_subscriptions_routesToTab4() {
        XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://subscriptions")!), 4)
    }
```

(If routing assertions are grouped in one test, add `XCTAssertEqual(RootView.tab(forDeepLink: URL(string: "goldengo://subscriptions")!), 4)` to that test instead.)

- [ ] **Step 5: Build + run the Features suite**

Run: `swift build` then `swift test --filter GoldengoFeaturesTests`
Expected: PASS (routing test green; everything compiles).

- [ ] **Step 6: Commit**

```bash
git add Sources/GoldengoFeatures/Subscriptions/ Sources/GoldengoFeatures/RootView.swift Tests/GoldengoFeaturesTests/
git commit -m "feat: Subscriptions tab — list candidates, confirm/dismiss, predicted next charge"
```

---

## Task 4 (OPTIONAL): Local pre-charge reminders

> **Scope note:** This is a spec "SHOULD" ("Optional local notification before the next charge"). It is **cuttable** — if the controller or reviewer decides to defer, stop after Task 3 and file a follow-up. The *decision logic* is a pure, tested function in Core; the OS glue is a thin, documented Features helper (not unit-tested, since `UNUserNotificationCenter` is a platform boundary).

**Files:**
- Create: `Sources/GoldengoCore/SubscriptionReminderPlanner.swift`
- Test: `Tests/GoldengoCoreTests/SubscriptionReminderPlannerTests.swift`
- Create: `Sources/GoldengoFeatures/Subscriptions/LocalNotificationScheduler.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoCoreTests/SubscriptionReminderPlannerTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class SubscriptionReminderPlannerTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    func test_schedulesReminderLeadDaysBeforeNextCharge() {
        let req = SubscriptionReminderPlanner.ReminderInput(
            id: "NETFLIX|monthly|ALL", title: "Netflix", body: "Renews tomorrow",
            nextCharge: day(2026, 4, 5))
        let out = SubscriptionReminderPlanner.plan([req], leadDays: 1, now: day(2026, 3, 1), calendar: cal)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: out[0].fireDate),
                       cal.dateComponents([.year, .month, .day], from: day(2026, 4, 4)))
    }

    func test_skipsRemindersInThePast() {
        let req = SubscriptionReminderPlanner.ReminderInput(
            id: "X|monthly|ALL", title: "X", body: "", nextCharge: day(2026, 1, 1))
        let out = SubscriptionReminderPlanner.plan([req], leadDays: 1, now: day(2026, 3, 1), calendar: cal)
        XCTAssertTrue(out.isEmpty)   // fire date (Dec 31) is before now
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter GoldengoCoreTests.SubscriptionReminderPlannerTests`
Expected: FAIL — type not defined.

- [ ] **Step 3: Write the planner**

Create `Sources/GoldengoCore/SubscriptionReminderPlanner.swift`:

```swift
import Foundation

/// Pure logic for *what* reminders to schedule and *when*. The OS scheduling glue lives in the
/// Features layer; this stays unit-testable.
public enum SubscriptionReminderPlanner {
    public struct ReminderInput: Sendable, Equatable {
        public var id: String
        public var title: String
        public var body: String
        public var nextCharge: Date
        public init(id: String, title: String, body: String, nextCharge: Date) {
            self.id = id; self.title = title; self.body = body; self.nextCharge = nextCharge
        }
    }
    public struct ReminderRequest: Sendable, Equatable {
        public var id: String
        public var title: String
        public var body: String
        public var fireDate: Date
    }

    /// Fire `leadDays` before each next-charge, dropping any whose fire date is already in the past.
    public static func plan(_ inputs: [ReminderInput], leadDays: Int, now: Date,
                            calendar: Calendar) -> [ReminderRequest] {
        inputs.compactMap { input in
            guard let fire = calendar.date(byAdding: .day, value: -leadDays, to: input.nextCharge),
                  fire >= now else { return nil }
            return ReminderRequest(id: input.id, title: input.title, body: input.body, fireDate: fire)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter GoldengoCoreTests.SubscriptionReminderPlannerTests`
Expected: PASS.

- [ ] **Step 5: Write the thin scheduler (Features)**

Create `Sources/GoldengoFeatures/Subscriptions/LocalNotificationScheduler.swift`:

```swift
import Foundation
import GoldengoCore
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Thin glue over `UNUserNotificationCenter`. Pure scheduling logic lives in
/// `SubscriptionReminderPlanner`; this only requests authorization and registers requests.
public enum LocalNotificationScheduler {
    /// Requests authorization (alert + sound). Returns whether granted. No-op off-device.
    public static func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        #else
        return false
        #endif
    }

    /// Replaces all subscription reminders with the given set (clears our namespace first).
    public static func schedule(_ requests: [SubscriptionReminderPlanner.ReminderRequest]) async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let ids = requests.map { "sub-reminder:\($0.id)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        for r in requests {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "sub-reminder:\(r.id)", content: content, trigger: trigger)
            try? await center.add(req)
        }
        #endif
    }
}
```

- [ ] **Step 6: Build + run Core suite**

Run: `swift build && swift test --filter GoldengoCoreTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/GoldengoCore/SubscriptionReminderPlanner.swift Tests/GoldengoCoreTests/SubscriptionReminderPlannerTests.swift Sources/GoldengoFeatures/Subscriptions/LocalNotificationScheduler.swift
git commit -m "feat: optional local pre-charge reminders (pure planner + thin UN scheduler)"
```

---

## Final verification (after all tasks)

- [ ] Run the **entire** suite: `swift test` — expected: all green (existing 82 + new Core/Data/Features tests).
- [ ] `swift build` clean (the app target compiles with the new tab).
- [ ] Confirm no `Co-Authored-By` trailer slipped into any commit (`git log --format='%an <%ae>%n%b' origin/main..HEAD`).

---

## Spec Coverage Self-Review

- **Group by normalized merchant + similar amount** → Task 1 `detect` (merchant+currency grouping; amount as median/flag, per Design Decision 1). ✅
- **Tolerance bands (weekly/monthly/quarterly/yearly)** → `SubscriptionCadence.dayBand`. ✅
- **≥3 occurrences, yearly ≥2** → `minimumOccurrences`. ✅
- **Free-trial handling** → `hadTrial`, test `test_freeTrialThenPaid...`. ✅
- **Variable amounts flag** → `isVariableAmount`, test `test_variableAmountUtility_flagged`. ✅
- **Occurrence counting uses merged records** → detection runs over already-merged `ExpenseRecord`s; same-day collapse adds belt-and-suspenders (Design Decision 2). ✅
- **Surface candidates, never silently assert; confirm/dismiss; predict next charge** → Task 2 (`isConfirmed`/`isDismissed`, decisions preserved) + Task 3 UI. ✅
- **Optional local notification before next charge** → Task 4 (optional). ✅
- **Unit-tested on fixtures (trials, annual, aliasing)** → Task 1 tests incl. `test_irregularIntervals_notDetected`, `test_detectsYearlyWithTwoOccurrences`, multi-currency, same-day. ✅

**Known limitations (documented, out of scope — file follow-up stories under GOL-7):**
- Two distinct subscriptions at the *same* merchant+currency collapse into one candidate (merchant-primary grouping).
- Only the four named cadences are detected (bi-weekly/6-weekly not surfaced).
- **Auto-match of future charges is deferred.** Spec §9 line 103 says confirmed subscriptions "auto-match future charges"; this MVP *predicts* `nextChargeDate` and re-detects on refresh, but does not yet link a newly-imported `ExpenseRecord` to a confirmed `SubscriptionRecord` (no `Expense.subscription` relationship). Re-running detection keeps the candidate fresh, which covers the user-visible need for now. Track as a follow-up.
