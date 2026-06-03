# GOL-67 Currency Converter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a pure, unit-tested `CurrencyConverter` over a cached exchange-rate table that converts between any of the ~162 currencies ExchangeRate-API serves, works offline from an App-Group cache (with a bundled real-data seed fallback), and surfaces staleness.

**Architecture:** Pure value types + converter live in `GoldengoCore` (dependency-free, mirroring `SubscriptionDetector`). The App-Group cache and the URLSession fetcher live in `GoldengoData` (which depends on Core). The app calls the fetcher once on launch. Resolution order everywhere is **cache → bundled seed**; the pure converter is identical regardless of which `RateTable` it gets.

**Tech Stack:** Swift 6 (strict concurrency), Foundation `Decimal`, `URLSession`, App-Group `UserDefaults`, XCTest. No new package dependencies and no `project.rb` change (only existing app files are modified; new files are inside SPM library targets and are globbed automatically).

**Spec:** [docs/superpowers/specs/2026-06-03-gol67-currency-converter-design.md](../specs/2026-06-03-gol67-currency-converter-design.md)

---

## File Structure

**Create (GoldengoCore — pure):**
- `Sources/GoldengoCore/RateTable.swift` — `RateTable` value type (base + rates + asOf), Codable.
- `Sources/GoldengoCore/CurrencyConverter.swift` — pure cross-rate converter + staleness.
- `Sources/GoldengoCore/ExchangeRateAPIResponse.swift` — Decodable DTO mapping the API JSON → `RateTable` (shared by the live fetch and the seed).
- `Sources/GoldengoCore/SeedRates.swift` — bundled real captured snapshot, decoded to a `RateTable`.

**Modify (GoldengoCore):**
- `Sources/GoldengoCore/CurrencyCode.swift` — broaden `fractionDigits` (ISO 4217 exceptions + lek override), `symbol` shortlist, add `popular`.

**Create (GoldengoData — persistence + networking):**
- `Sources/GoldengoData/ExchangeRateCache.swift` — App-Group `UserDefaults` cache (mirrors `SharedSummary`).
- `Sources/GoldengoData/ExchangeRateService.swift` — `refreshIfNeeded` (staleness gate + URLSession fetch + save).

**Modify (app):**
- `AppProject/Goldengo/GoldengoStore.swift` — add `refreshExchangeRates()` helper.
- `AppProject/Goldengo/GoldengoApp.swift` — `.task` to refresh on launch.

**Create (tests):**
- `Tests/GoldengoCoreTests/CurrencyCodeMetadataTests.swift`
- `Tests/GoldengoCoreTests/RateTableTests.swift`
- `Tests/GoldengoCoreTests/CurrencyConverterTests.swift`
- `Tests/GoldengoCoreTests/ExchangeRateAPIResponseTests.swift`
- `Tests/GoldengoCoreTests/SeedRatesTests.swift`
- `Tests/GoldengoDataTests/ExchangeRateCacheTests.swift`

---

## Task 1: Broaden `CurrencyCode` metadata

**Files:**
- Modify: `Sources/GoldengoCore/CurrencyCode.swift`
- Test: `Tests/GoldengoCoreTests/CurrencyCodeMetadataTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoCoreTests/CurrencyCodeMetadataTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class CurrencyCodeMetadataTests: XCTestCase {
    // ISO 4217 zero-decimal currencies must render with no minor unit.
    func test_fractionDigits_isoZeroDecimalCurrencies() {
        XCTAssertEqual(CurrencyCode("JPY").fractionDigits, 0)
        XCTAssertEqual(CurrencyCode("KRW").fractionDigits, 0)
        XCTAssertEqual(CurrencyCode("ISK").fractionDigits, 0)
        XCTAssertEqual(CurrencyCode("XOF").fractionDigits, 0)
    }

    // ISO 4217 three-decimal currencies (Gulf dinars etc.).
    func test_fractionDigits_threeDecimalCurrencies() {
        XCTAssertEqual(CurrencyCode("BHD").fractionDigits, 3)
        XCTAssertEqual(CurrencyCode("KWD").fractionDigits, 3)
        XCTAssertEqual(CurrencyCode("TND").fractionDigits, 3)
    }

    // Lek is displayed whole — a deliberate product override of ISO 4217 (which says 2).
    func test_fractionDigits_lekStaysZeroByProductChoice() {
        XCTAssertEqual(CurrencyCode.all.fractionDigits, 0)
    }

    // Everything else, including unknown codes, defaults to 2.
    func test_fractionDigits_defaultsToTwo() {
        XCTAssertEqual(CurrencyCode.eur.fractionDigits, 2)
        XCTAssertEqual(CurrencyCode("USD").fractionDigits, 2)
        XCTAssertEqual(CurrencyCode("ZZZ").fractionDigits, 2)
    }

    func test_symbol_knownAndUnknownFallback() {
        XCTAssertEqual(CurrencyCode("USD").symbol, "$")
        XCTAssertEqual(CurrencyCode("JPY").symbol, "¥")
        XCTAssertEqual(CurrencyCode.all.symbol, "L")
        XCTAssertEqual(CurrencyCode("ZZZ").symbol, "ZZZ") // unknown → ISO code
    }

    func test_popular_startsWithLekAndEuro_andHasNoDuplicates() {
        XCTAssertEqual(Array(CurrencyCode.popular.prefix(2)), [.all, .eur])
        XCTAssertEqual(Set(CurrencyCode.popular).count, CurrencyCode.popular.count)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CurrencyCodeMetadataTests`
Expected: FAIL — `CurrencyCode` has no `popular`; `fractionDigits`/`symbol` don't yet handle JPY/BHD/USD.

- [ ] **Step 3: Replace `CurrencyCode.swift` with the broadened version**

Overwrite `Sources/GoldengoCore/CurrencyCode.swift`:

```swift
public struct CurrencyCode: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public static let all = CurrencyCode("ALL")   // Albanian lek
    public static let eur = CurrencyCode("EUR")

    /// ISO 4217 currencies whose minor unit is 0 decimal digits (verified 2026-06-03 against
    /// the ISO 4217 table: en.wikipedia.org/wiki/ISO_4217).
    private static let isoZeroDigit: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF",
        "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
    ]
    /// ISO 4217 three-decimal currencies (verified 2026-06-03).
    private static let threeDigit: Set<String> = ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"]
    /// Display override: lek is shown without its (rarely used in practice) minor unit, matching
    /// the app's prior single-currency behaviour. ISO 4217 nominally assigns lek 2 digits.
    private static let displayZeroDigit: Set<String> = isoZeroDigit.union(["ALL"])

    /// Unambiguous display symbols; codes that share a glyph (e.g. CAD/AUD/SGD all "$") are left
    /// to fall back to the ISO code so the user is never shown an ambiguous symbol.
    private static let symbols: [String: String] = [
        "ALL": "L", "EUR": "€", "USD": "$", "GBP": "£", "JPY": "¥", "CNY": "¥", "INR": "₹",
        "RUB": "₽", "TRY": "₺", "BRL": "R$", "KRW": "₩", "CHF": "Fr", "PLN": "zł", "THB": "฿",
        "VND": "₫", "UAH": "₴", "ILS": "₪", "PHP": "₱", "NGN": "₦", "ZAR": "R"
    ]

    /// Common currencies surfaced at the top of pickers (GOL-65/66). The full universe is "any
    /// code present in the rate table"; this is just the convenience shortcut group.
    public static let popular: [CurrencyCode] = [
        .all, .eur, CurrencyCode("USD"), CurrencyCode("GBP"), CurrencyCode("JPY"),
        CurrencyCode("CHF"), CurrencyCode("CAD"), CurrencyCode("AUD"), CurrencyCode("CNY"),
        CurrencyCode("INR"), CurrencyCode("AED"), CurrencyCode("TRY")
    ]

    /// Display symbol; falls back to the raw code (e.g. crypto tickers, ambiguous "$" currencies).
    public var symbol: String {
        Self.symbols[rawValue] ?? rawValue
    }

    /// Minor-unit decimal digits for everyday display. Default 2; ISO 4217 exceptions for 0/3;
    /// plus the lek display override.
    public var fractionDigits: Int {
        if Self.threeDigit.contains(rawValue) { return 3 }
        if Self.displayZeroDigit.contains(rawValue) { return 0 }
        return 2
    }
}
```

- [ ] **Step 4: Run tests to verify they pass (incl. existing MoneyTests, which lock lek=0/EUR=2)**

Run: `swift test --filter GoldengoCoreTests`
Expected: PASS — new metadata tests pass and `MoneyTests` (e.g. `test_lek_formatsWithSymbol_noDecimals`, `test_unknownCurrency_usesRawCodeAsSymbol`) still pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/CurrencyCode.swift Tests/GoldengoCoreTests/CurrencyCodeMetadataTests.swift
git commit -m "feat(core): broaden CurrencyCode metadata (ISO 4217 fraction digits, symbols, popular)"
```

---

## Task 2: `RateTable` value type

**Files:**
- Create: `Sources/GoldengoCore/RateTable.swift`
- Test: `Tests/GoldengoCoreTests/RateTableTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoCoreTests/RateTableTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class RateTableTests: XCTestCase {
    // The cache serializes RateTable to JSON; encode→decode must preserve everything exactly,
    // including Decimal precision (so cached rates don't drift).
    func test_codableRoundTrip_preservesBaseRatesAndDate() throws {
        let table = RateTable(
            base: CurrencyCode("USD"),
            rates: ["USD": 1, "EUR": Decimal(string: "0.859836")!, "ALL": Decimal(string: "81.946489")!],
            asOf: Date(timeIntervalSince1970: 1_748_908_800)
        )
        let data = try JSONEncoder().encode(table)
        let decoded = try JSONDecoder().decode(RateTable.self, from: data)
        XCTAssertEqual(decoded, table)
        XCTAssertEqual(decoded.rates["ALL"], Decimal(string: "81.946489")!)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RateTableTests`
Expected: FAIL — `RateTable` type does not exist.

- [ ] **Step 3: Create `RateTable.swift`**

```swift
import Foundation

/// A snapshot of exchange rates relative to a base currency, with the time they were published.
/// `Decimal` (not `Double`) so cached/seeded values carry no floating-point drift.
public struct RateTable: Sendable, Equatable, Codable {
    public let base: CurrencyCode          // e.g. USD
    public let rates: [String: Decimal]    // units of <code> per 1 base; base maps to 1
    public let asOf: Date                  // when these rates were published

    public init(base: CurrencyCode, rates: [String: Decimal], asOf: Date) {
        self.base = base
        self.rates = rates
        self.asOf = asOf
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RateTableTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/RateTable.swift Tests/GoldengoCoreTests/RateTableTests.swift
git commit -m "feat(core): add RateTable value type"
```

---

## Task 3: `CurrencyConverter` (the keystone)

**Files:**
- Create: `Sources/GoldengoCore/CurrencyConverter.swift`
- Test: `Tests/GoldengoCoreTests/CurrencyConverterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoCoreTests/CurrencyConverterTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class CurrencyConverterTests: XCTestCase {
    // USD-base table: 1 USD = 100 ALL = 0.9 EUR.
    private func table(asOf: Date = Date(timeIntervalSince1970: 1_000_000)) -> RateTable {
        RateTable(base: CurrencyCode("USD"),
                  rates: ["USD": 1, "ALL": 100, "EUR": Decimal(string: "0.9")!],
                  asOf: asOf)
    }

    // Same-currency conversion is identity — even when that currency is absent from the table.
    func test_sameCurrency_returnsAmountUnchanged() throws {
        let thin = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1], asOf: .init())
        let c = CurrencyConverter(table: thin)
        XCTAssertEqual(try c.convert(42, from: .eur, to: .eur), 42)
    }

    // Cross-rate goes through the base: 100 ALL → EUR = 100 * 0.9 / 100 = 0.9.
    func test_crossRate_isComputedThroughBase() throws {
        let c = CurrencyConverter(table: table())
        XCTAssertEqual(try c.convert(100, from: .all, to: .eur), Decimal(string: "0.9")!)
    }

    // Conversion must be reversible within rounding tolerance (catches inverted ratios).
    func test_roundTrip_returnsApproximatelyOriginal() throws {
        let c = CurrencyConverter(table: table())
        let there = try c.convert(1234, from: .all, to: .eur)
        let back = try c.convert(there, from: .eur, to: .all)
        XCTAssertLessThan(abs(back - 1234), Decimal(string: "0.0001")!)
    }

    // A missing rate must throw — we never silently fabricate a rate.
    func test_missingRate_throws() {
        let c = CurrencyConverter(table: table())
        XCTAssertThrowsError(try c.convert(1, from: CurrencyCode("XYZ"), to: .eur)) { error in
            XCTAssertEqual(error as? CurrencyConverter.ConversionError, .missingRate(CurrencyCode("XYZ")))
        }
    }

    // Money convenience overload tags the result with the target currency.
    func test_convertMoney_setsTargetCurrency() throws {
        let c = CurrencyConverter(table: table())
        let out = try c.convert(Money(amount: 100, currency: .all), to: .eur)
        XCTAssertEqual(out, Money(amount: Decimal(string: "0.9")!, currency: .eur))
    }

    // Staleness flips exactly at maxAge past asOf.
    func test_isStale_boundary() {
        let asOf = Date(timeIntervalSince1970: 1_000_000)
        let c = CurrencyConverter(table: table(asOf: asOf))
        XCTAssertFalse(c.isStale(asOf: asOf.addingTimeInterval(3599), maxAge: 3600))
        XCTAssertTrue(c.isStale(asOf: asOf.addingTimeInterval(3601), maxAge: 3600))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CurrencyConverterTests`
Expected: FAIL — `CurrencyConverter` does not exist.

- [ ] **Step 3: Create `CurrencyConverter.swift`**

```swift
import Foundation

/// Pure, dependency-free converter over a `RateTable`. Returns UNROUNDED `Decimal` so callers can
/// sum many conversions and round once at display time (avoids accumulation error).
public struct CurrencyConverter: Sendable {
    public let table: RateTable

    public init(table: RateTable) {
        self.table = table
    }

    public enum ConversionError: Error, Equatable {
        case missingRate(CurrencyCode)
    }

    /// Cross-rate through the base: `(amount * rate[to]) / rate[from]`. Same-currency is identity.
    public func convert(_ amount: Decimal, from: CurrencyCode, to: CurrencyCode) throws -> Decimal {
        if from == to { return amount }
        guard let rateFrom = table.rates[from.rawValue] else { throw ConversionError.missingRate(from) }
        guard let rateTo = table.rates[to.rawValue] else { throw ConversionError.missingRate(to) }
        return (amount * rateTo) / rateFrom
    }

    /// Convenience: convert a `Money` and re-tag it with the target currency.
    public func convert(_ money: Money, to: CurrencyCode) throws -> Money {
        Money(amount: try convert(money.amount, from: money.currency, to: to), currency: to)
    }

    /// True when the table is older than `maxAge` relative to `now`.
    public func isStale(asOf now: Date, maxAge: TimeInterval) -> Bool {
        now.timeIntervalSince(table.asOf) > maxAge
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CurrencyConverterTests`
Expected: PASS (all 6)

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/CurrencyConverter.swift Tests/GoldengoCoreTests/CurrencyConverterTests.swift
git commit -m "feat(core): add pure CurrencyConverter (cross-rate, round-trip, staleness)"
```

---

## Task 4: `ExchangeRateAPIResponse` DTO

**Files:**
- Create: `Sources/GoldengoCore/ExchangeRateAPIResponse.swift`
- Test: `Tests/GoldengoCoreTests/ExchangeRateAPIResponseTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/GoldengoCoreTests/ExchangeRateAPIResponseTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class ExchangeRateAPIResponseTests: XCTestCase {
    // The real API shape (subset): result/base_code/time_last_update_unix/rates → RateTable.
    func test_decode_mapsToRateTable_usingUnixTimestamp() throws {
        let json = """
        {"result":"success","base_code":"USD","time_last_update_unix":1748908800,
         "time_last_update_utc":"Wed, 03 Jun 2026 00:02:31 +0000",
         "rates":{"USD":1,"EUR":0.859836,"ALL":81.946489}}
        """
        let dto = try JSONDecoder().decode(ExchangeRateAPIResponse.self, from: Data(json.utf8))
        let table = try XCTUnwrap(dto.toRateTable())
        XCTAssertEqual(table.base, CurrencyCode("USD"))
        XCTAssertEqual(table.rates["ALL"], Decimal(string: "81.946489")!)
        XCTAssertEqual(table.asOf, Date(timeIntervalSince1970: 1_748_908_800))
    }

    // Falls back to the RFC1123 UTC string if the unix field is absent.
    func test_decode_fallsBackToUtcStringWhenNoUnix() throws {
        let json = """
        {"result":"success","base_code":"USD",
         "time_last_update_utc":"Wed, 03 Jun 2026 00:02:31 +0000",
         "rates":{"USD":1,"EUR":0.86}}
        """
        let dto = try JSONDecoder().decode(ExchangeRateAPIResponse.self, from: Data(json.utf8))
        let table = try XCTUnwrap(dto.toRateTable())
        XCTAssertEqual(table.asOf.timeIntervalSince1970, 1_748_908_951, accuracy: 1) // 2026-06-03 00:02:31Z
    }

    // A non-success payload yields nil (caller keeps the prior cache).
    func test_decode_nonSuccessYieldsNil() throws {
        let json = #"{"result":"error","base_code":"USD","rates":{}}"#
        let dto = try JSONDecoder().decode(ExchangeRateAPIResponse.self, from: Data(json.utf8))
        XCTAssertNil(dto.toRateTable())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ExchangeRateAPIResponseTests`
Expected: FAIL — `ExchangeRateAPIResponse` does not exist.

- [ ] **Step 3: Create `ExchangeRateAPIResponse.swift`**

```swift
import Foundation

/// Decodable mapping of the ExchangeRate-API open-endpoint JSON onto a `RateTable`. Pure (no
/// networking) so it is shared by the live fetch (GoldengoData) and the bundled seed.
public struct ExchangeRateAPIResponse: Decodable, Sendable {
    public let result: String
    public let baseCode: String
    public let timeLastUpdateUnix: TimeInterval?
    public let timeLastUpdateUtc: String?
    public let rates: [String: Decimal]

    enum CodingKeys: String, CodingKey {
        case result, rates
        case baseCode = "base_code"
        case timeLastUpdateUnix = "time_last_update_unix"
        case timeLastUpdateUtc = "time_last_update_utc"
    }

    /// Builds a `RateTable`, or nil if the payload isn't a usable success response.
    public func toRateTable() -> RateTable? {
        guard result == "success", !rates.isEmpty else { return nil }
        let asOf: Date
        if let unix = timeLastUpdateUnix {
            asOf = Date(timeIntervalSince1970: unix)
        } else if let utc = timeLastUpdateUtc, let parsed = Self.rfc1123.date(from: utc) {
            asOf = parsed
        } else {
            return nil
        }
        return RateTable(base: CurrencyCode(baseCode), rates: rates, asOf: asOf)
    }

    /// e.g. "Wed, 03 Jun 2026 00:02:31 +0000". POSIX locale → locale-independent parsing.
    private static let rfc1123: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ExchangeRateAPIResponseTests`
Expected: PASS (all 3)

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/ExchangeRateAPIResponse.swift Tests/GoldengoCoreTests/ExchangeRateAPIResponseTests.swift
git commit -m "feat(core): add ExchangeRateAPIResponse DTO → RateTable"
```

---

## Task 5: Bundled seed snapshot (real data — no hand-typing)

**Files:**
- Create: `Sources/GoldengoCore/SeedRates.swift`
- Test: `Tests/GoldengoCoreTests/SeedRatesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoCoreTests/SeedRatesTests.swift`:

```swift
import XCTest
@testable import GoldengoCore

final class SeedRatesTests: XCTestCase {
    // The bundled seed must always be usable so first-run-while-offline never crashes.
    func test_seedDecodes_hasManyCurrencies_andConverts() throws {
        let table = SeedRates.table
        XCTAssertEqual(table.base, CurrencyCode("USD"))
        XCTAssertGreaterThan(table.rates.count, 100) // real snapshot carries ~162 codes
        XCTAssertNotNil(table.rates["ALL"])
        XCTAssertNotNil(table.rates["EUR"])
        // Offline conversion path works end-to-end.
        let eur = try CurrencyConverter(table: table).convert(1000, from: .all, to: .eur)
        XCTAssertGreaterThan(eur, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SeedRatesTests`
Expected: FAIL — `SeedRates` does not exist.

- [ ] **Step 3: Capture the REAL snapshot and create `SeedRates.swift`**

First capture the live response (do NOT hand-type rates):

```bash
curl -s 'https://open.er-api.com/v6/latest/USD' -o /tmp/goldengo-seed.json
# sanity check it succeeded and is the full payload:
grep -o '"result":"success"' /tmp/goldengo-seed.json && wc -c /tmp/goldengo-seed.json
```

Then create `Sources/GoldengoCore/SeedRates.swift`, pasting the **entire** contents of
`/tmp/goldengo-seed.json` verbatim between the `"""` delimiters (the JSON's double quotes are
safe inside a Swift multiline string). Keep the surrounding code exactly as below:

```swift
import Foundation

/// A real captured snapshot of the ExchangeRate-API response (open.er-api.com/v6/latest/USD),
/// compiled in as the last-resort offline fallback. Captured 2026-06-03. Its old `asOf` makes it
/// read as stale; the live cache is always preferred over it. Compiled-in (not a Bundle resource)
/// so it can never fail to load. The exact values are validated by `SeedRatesTests`.
public enum SeedRates {
    /// PASTE the full /tmp/goldengo-seed.json payload here, unedited.
    static let json = """
    <PASTE CAPTURED JSON HERE>
    """

    /// Decoded once. A guaranteed-safe minimal fallback covers the impossible decode-failure case
    /// (the JSON is a build-time constant the test pins), so this never throws at runtime.
    public static let table: RateTable = {
        if let dto = try? JSONDecoder().decode(ExchangeRateAPIResponse.self, from: Data(json.utf8)),
           let t = dto.toRateTable() {
            return t
        }
        return RateTable(base: CurrencyCode("USD"), rates: ["USD": 1], asOf: Date(timeIntervalSince1970: 0))
    }()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SeedRatesTests`
Expected: PASS. If it fails on `rates.count > 100`, the JSON wasn't pasted fully — re-capture and paste the whole payload.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoCore/SeedRates.swift Tests/GoldengoCoreTests/SeedRatesTests.swift
git commit -m "feat(core): bundle real ExchangeRate-API seed snapshot for offline fallback"
```

---

## Task 6: `ExchangeRateCache` (App-Group persistence)

**Files:**
- Create: `Sources/GoldengoData/ExchangeRateCache.swift`
- Test: `Tests/GoldengoDataTests/ExchangeRateCacheTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/GoldengoDataTests/ExchangeRateCacheTests.swift`:

```swift
import XCTest
import GoldengoCore
@testable import GoldengoData

final class ExchangeRateCacheTests: XCTestCase {
    // A dedicated suite so the test never touches the real App Group defaults.
    private let suite = "test.goldengo.fxcache"

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func test_load_isNilBeforeAnySave() {
        let cache = ExchangeRateCache(suiteName: suite)
        XCTAssertNil(cache.load())
    }

    func test_saveThenLoad_roundTripsTheTable() {
        let cache = ExchangeRateCache(suiteName: suite)
        let table = RateTable(base: CurrencyCode("USD"),
                              rates: ["USD": 1, "ALL": Decimal(string: "81.95")!],
                              asOf: Date(timeIntervalSince1970: 1_748_908_800))
        cache.save(table)
        XCTAssertEqual(cache.load(), table)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ExchangeRateCacheTests`
Expected: FAIL — `ExchangeRateCache` does not exist.

- [ ] **Step 3: Create `ExchangeRateCache.swift`**

```swift
import Foundation
import GoldengoCore

/// App-Group cache for the latest `RateTable`, mirroring `SharedSummary`'s UserDefaults pattern.
public struct ExchangeRateCache {
    private let defaults: UserDefaults
    private static let key = "exchangeRateTable"

    public init(suiteName: String? = SharedSummary.appGroupID) {
        defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The last cached table, or nil if nothing has been fetched yet.
    public func load() -> RateTable? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(RateTable.self, from: data)
    }

    public func save(_ table: RateTable) {
        guard let data = try? JSONEncoder().encode(table) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ExchangeRateCacheTests`
Expected: PASS (both)

- [ ] **Step 5: Commit**

```bash
git add Sources/GoldengoData/ExchangeRateCache.swift Tests/GoldengoDataTests/ExchangeRateCacheTests.swift
git commit -m "feat(data): add App-Group ExchangeRateCache"
```

---

## Task 7: `ExchangeRateService` (staleness gate + fetch)

**Files:**
- Create: `Sources/GoldengoData/ExchangeRateService.swift`

This task is networking glue: its parsing is already covered by Task 4, its persistence by Task 6.
It is verified by **build** here and by **runtime** in Task 9 (no network in CI).

- [ ] **Step 1: Create `ExchangeRateService.swift`**

```swift
import Foundation
import OSLog
import GoldengoCore

/// Refreshes the App-Group rate cache from ExchangeRate-API's free, key-less open endpoint.
/// Fully offline-safe: any failure leaves the existing cache untouched and never throws to callers.
public struct ExchangeRateService: Sendable {
    private static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!
    private static let log = Logger(subsystem: "com.goldengo.app", category: "fx")

    public init() {}

    /// Fetches fresh rates only when the cache is missing or older than `maxAge`.
    public func refreshIfNeeded(now: Date = .now,
                                maxAge: TimeInterval = 12 * 3600,
                                suiteName: String? = SharedSummary.appGroupID) async {
        let cache = ExchangeRateCache(suiteName: suiteName)
        if let existing = cache.load(), now.timeIntervalSince(existing.asOf) < maxAge {
            Self.log.debug("FX cache fresh (asOf \(existing.asOf, privacy: .public)); skipping fetch")
            return
        }
        guard let table = await fetchLatest() else { return }
        cache.save(table)
        Self.log.info("FX cache updated: \(table.rates.count, privacy: .public) rates, asOf \(table.asOf, privacy: .public)")
    }

    /// Single GET → DTO → RateTable. Returns nil on any network/HTTP/decode failure.
    func fetchLatest() async -> RateTable? {
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.endpoint)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                Self.log.error("FX fetch non-200")
                return nil
            }
            return try JSONDecoder().decode(ExchangeRateAPIResponse.self, from: data).toRateTable()
        } catch {
            Self.log.error("FX fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles (strict concurrency)**

Run: `swift build`
Expected: Builds with no errors or Sendable warnings.

- [ ] **Step 3: Run the whole unit suite to confirm nothing regressed**

Run: `swift test`
Expected: PASS — all prior tests plus the new ones (≥ 142 + the tests added here).

- [ ] **Step 4: Commit**

```bash
git add Sources/GoldengoData/ExchangeRateService.swift
git commit -m "feat(data): add offline-safe ExchangeRateService"
```

---

## Task 8: Wire the launch refresh

**Files:**
- Modify: `AppProject/Goldengo/GoldengoStore.swift`
- Modify: `AppProject/Goldengo/GoldengoApp.swift`

No `project.rb` change — both files already exist in the app target.

- [ ] **Step 1: Add the refresh helper to `GoldengoStore`**

In `AppProject/Goldengo/GoldengoStore.swift`, replace the closing of the enum (the last method + brace, currently lines 40–41):

```swift
    public static func shared() -> IngestionStore { IngestionStore(modelContainer: container) }
}
```

with:

```swift
    public static func shared() -> IngestionStore { IngestionStore(modelContainer: container) }

    /// Refresh the exchange-rate cache on launch (no-op if the cache is still fresh). Offline-safe.
    public static func refreshExchangeRates() async {
        await ExchangeRateService().refreshIfNeeded()
    }
}
```

- [ ] **Step 2: Call it on launch in `GoldengoApp`**

In `AppProject/Goldengo/GoldengoApp.swift`, replace the `WindowGroup` body (currently lines 36–38):

```swift
        WindowGroup {
            RootView(store: GoldengoStore.shared())
        }
```

with:

```swift
        WindowGroup {
            RootView(store: GoldengoStore.shared())
                .task { await GoldengoStore.refreshExchangeRates() }
        }
```

- [ ] **Step 3: Build the app for the simulator**

Run:
```bash
xcodebuild -project AppProject/Goldengo.xcodeproj -scheme Goldengo \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath AppProject/.build build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add AppProject/Goldengo/GoldengoStore.swift AppProject/Goldengo/GoldengoApp.swift
git commit -m "feat(app): refresh exchange-rate cache on launch"
```

---

## Task 9: Runtime verification + review (project convention — tests-green ≠ works)

**Files:** none (verification only).

- [ ] **Step 1: Launch in the simulator with seeded data and capture logs**

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null || true
xcrun simctl install booted "$(find AppProject/.build -name 'Goldengo.app' -path '*Debug-iphonesimulator*' | head -1)"
SIMCTL_CHILD_GOLDENGO_SEED_SAMPLE=1 xcrun simctl launch booted com.goldengo.app
# give the launch fetch a few seconds, then inspect logs:
xcrun simctl spawn booted log show --last 30s --predicate 'process == "Goldengo"' | grep -Ei 'fx|AttributeGraph|modifying state|hang'
```
Expected: an `info`-level `FX cache updated: <N> rates, asOf <date>` line (online), and **no**
AttributeGraph cycles / "modifying state" / hangs. Offline (disable the Mac's network first), expect
a `FX fetch failed` line and **no crash** — the app still launches (seed/cache covers reads).

- [ ] **Step 2: Confirm the cache actually populated**

Re-launch (second cold launch within 12h) and confirm the log now reads
`FX cache fresh (asOf …); skipping fetch` — proving `save`/`load` round-tripped through the App Group.

- [ ] **Step 3: Second-Opus reviewer over the diff**

Dispatch a general-purpose **Opus 4.8** reviewer agent over `git diff main...HEAD` for GOL-67. Focus:
pure/​impure boundary intact, Sendable/strict-concurrency cleanliness, no `Decimal`↔`Double` drift,
offline/first-run safety, tests encode intent (Rule 9). Fix all findings; re-run `swift test`.

- [ ] **Step 4: Final green gate**

Run: `swift test`
Expected: PASS. Then the branch is ready to ff-merge to `main`.

---

## Self-Review

**1. Spec coverage:**
- Pure converter + tests (identity, cross-rate, round-trip, missing-rate, staleness) → Task 3. ✓
- `RateTable` + Codable cache survival → Tasks 2, 6. ✓
- Live API source, DTO mapping (unix + UTC fallback, non-success → nil) → Tasks 4, 7. ✓
- All-currency support → converter is code-agnostic (Task 3); seed carries the full ~162 (Task 5). ✓
- App-Group cache + offline fallback + "no crash offline/first-run" → Tasks 5 (seed), 6 (cache), 7 (offline-safe service), 9 (runtime offline check). ✓
- Staleness surfaced → `isStale` + `asOf` (Task 3); consumed by GOL-68 (out of scope). ✓
- Broadened `CurrencyCode` (ISO 4217 fraction digits, symbols, popular) → Task 1. ✓
- Refresh cadence 12h, rounding-at-display (converter unrounded), attribution → encoded in Task 7 (`maxAge`), Task 3 (unrounded), and deferred-to-GOL-66 for the Settings attribution line (noted out of scope). ✓
- Runtime verification + second-Opus review → Task 9. ✓

**2. Placeholder scan:** The only `<PASTE …>` is Task 5's seed JSON — a deterministic capture step with an exact `curl` command and a test that fails if the payload is incomplete, not an undecided placeholder. No "TBD"/"add error handling"/"similar to Task N".

**3. Type consistency:** `RateTable(base:rates:asOf:)`, `CurrencyConverter(table:)`, `ConversionError.missingRate`, `ExchangeRateAPIResponse.toRateTable()`, `ExchangeRateCache(suiteName:).load()/save()`, `ExchangeRateService().refreshIfNeeded()/fetchLatest()`, `GoldengoStore.refreshExchangeRates()` — names/signatures used identically across tasks and the launch wiring. `CurrencyCode.popular`, `.fractionDigits`, `.symbol` consistent with Task 1.
