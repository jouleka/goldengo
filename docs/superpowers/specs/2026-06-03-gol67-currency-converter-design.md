# GOL-67 — Exchange-rate provider: pure converter + cache + offline fallback

**Ticket:** [GOL-67](https://mysigner.youtrack.cloud/issue/GOL-67) (keystone of epic [GOL-63](https://mysigner.youtrack.cloud/issue/GOL-63), multi-currency).
**Status:** design approved (FX source + "all currencies"); pending spec review.
**Date:** 2026-06-03.

## Goal

Introduce an FX source so the app can convert between any supported currencies at the
**current** rate. Keep the conversion logic **pure + unit-tested** (a `CurrencyConverter`
over a rate table, mirroring `SubscriptionDetector`'s dependency-free style). Cache the
latest rates in the App Group with a timestamp; work **offline** from the last cache;
surface staleness ("rate as of <date>"). Must not crash offline or on first run.

This ticket ships **only** the converter + cache + fetcher + seed + tests, plus the
broadened `CurrencyCode` metadata. It does **not** wire dashboard totals, settings,
Quick-Add pickers, or the flip toggle — those are GOL-66/68/69/65.

## Decision record

- **FX source: live API, auto-refresh** (user-chosen over manual entry / hybrid). Rationale:
  best fit for the product's hard constraint ("the user shouldn't have to think about
  anything") — zero user effort, always current.
- **Support all currencies the API returns** (~162), not a curated pair/subset — "don't
  close off markets because we don't support their currency" (user). The converter is
  currency-agnostic (works on any code in the table), so this is free at the logic layer.
- **Provider: ExchangeRate-API open endpoint** `https://open.er-api.com/v6/latest/USD`.
  Verified live on 2026-06-03: `result:"success"`, **no API key**, **162 currencies**
  including ALL (lek), EUR, USD, GBP, JPY, CNY, …; base USD; `time_last_update_utc` present;
  updates ~once/day (`time_next_update_utc` ≈ +24h). Free tier requests attribution.

## Components

All pure types live in **GoldengoCore** (dependency-free, unit-tested). Persistence and
networking live in **GoldengoData** (next to `SharedSummary` / `IngestionStore`).

### 1. `CurrencyCode` (GoldengoCore) — broadened metadata

`CurrencyCode` already accepts any raw code and special-cases ALL/EUR for `symbol`
(`fractionDigits`). Broaden it so all currencies display correctly:

- **`fractionDigits`** — default `2`, with a fact-checked **exception set** from ISO 4217
  (source: ISO 4217 table, en.wikipedia.org/wiki/ISO_4217, verified 2026-06-03):
  - **0 digits:** BIF, CLP, DJF, GNF, ISK, JPY, KMF, KRW, PYG, RWF, UGX, VND, VUV, XAF, XOF, XPF
  - **3 digits:** BHD, IQD, JOD, KWD, LYD, OMR, TND
  - Everything else → `2`. (CLF/UYW 4-digit index units and metals XAU/XAG/XPD/XPT/XDR are
    left at the default; they are not spendable everyday currencies and need no special
    casing. Preserves today's ALL=0/EUR=2 behaviour.)
- **`symbol`** — keep a small shortlist of unambiguous symbols (e.g. `L` ALL, `€` EUR,
  `$` USD, `£` GBP, `¥` JPY, `₹` INR, `₽` RUB, `₺` TRY, `R$` BRL, `Fr` CHF, `kr` SEK/NOK/DKK,
  `zł` PLN, `₩` KRW, `₣`/`Fr` etc.). Any code not in the shortlist falls back to the **ISO
  code itself** (today's behaviour) — unambiguous for the long tail (CAD/AUD/SGD all "$"
  would be confusing as symbols, so they render as codes).
- **`CurrencyCode.popular: [CurrencyCode]`** — a curated shortlist (~12: ALL, EUR, USD, GBP,
  JPY, CHF, CAD, AUD, CNY, INR, AED, TRY) for surfacing common choices at the top of pickers.
  The full universe for pickers (GOL-65/66) is "all codes present in the rate table"; this is
  just the convenience shortcut group.

Hardcoded (not `Locale`-derived) for determinism and CI-safety on the macOS test build,
matching the existing ALL/EUR hardcoding (Rule 11 — match conventions).

### 2. `RateTable` (GoldengoCore) — pure value type

```swift
public struct RateTable: Sendable, Equatable, Codable {
    public let base: CurrencyCode        // e.g. USD
    public let rates: [String: Decimal]  // units of <code> per 1 base; base maps to 1
    public let asOf: Date                // when these rates were published
}
```

`Decimal` (not `Double`) so cached/seeded values carry no float drift. `Codable` for both
cache persistence and the bundled seed.

### 3. `CurrencyConverter` (GoldengoCore) — the keystone, pure

```swift
public struct CurrencyConverter: Sendable {
    public let table: RateTable
    public init(table: RateTable)

    public enum ConversionError: Error, Equatable { case missingRate(CurrencyCode) }

    /// Cross-rate through the base: (amount * rate[to]) / rate[from].
    public func convert(_ amount: Decimal, from: CurrencyCode, to: CurrencyCode) throws -> Decimal
    public func convert(_ money: Money, to: CurrencyCode) throws -> Money   // convenience

    public func isStale(asOf now: Date, maxAge: TimeInterval) -> Bool
}
```

- `from == to` → returns `amount` unchanged (identity short-circuit; works even if a rate is
  absent — keeps same-currency totals safe on a thin/seed table).
- Otherwise requires `rate[from]` and `rate[to]`; missing either → throws
  `.missingRate(code)`. Result is **unrounded** — precision preserved for summing and
  round-trips. Display/rounding happens later via the existing `Money.formatted()`.
- One multiply then one divide (minimises division rounding error).

### 4. Seed `RateTable` (GoldengoCore) — bundled offline fallback

A **real captured snapshot** of the live response, compiled in as a JSON string constant and
decoded once at first use:

```swift
enum SeedRates {
    static let json = "..."   // captured verbatim from open.er-api.com (all ~162 codes)
    static let table: RateTable = decode(json)   // build-time-correct; a test asserts it decodes
}
```

- Generated by a small dev script that calls the endpoint and emits the constant — **not
  hand-typed** (per the fact-check directive). Decoded via the same DTO as the live fetch
  (below), so one parser, one code path.
- Compiled-in (no `Bundle.module` lookup) so the last-resort fallback **cannot fail to load**.
  `asOf` is the capture date, so it reads as clearly stale and is the resolution fallback,
  never preferred over a fresher cache.
- Guarantees "no crash offline / first-run": there is always a usable table.

### 5. `ExchangeRateCache` (GoldengoData) — App-Group persistence

Mirrors `SharedSummary` exactly (`UserDefaults(suiteName: "group.com.goldengo.app")`, with
`.standard` fallback):

```swift
public struct ExchangeRateCache {
    public init(suiteName: String? = SharedSummary.appGroupID)
    public func load() -> RateTable?      // nil until first successful fetch
    public func save(_ table: RateTable)  // JSON-encoded under one key
}
```

### 6. `ExchangeRateService` (GoldengoData) — the only impure edge

```swift
public struct ExchangeRateAPIResponse: Decodable {  // DTO → RateTable (maps base_code, rates, time_last_update_unix)
    func toRateTable() -> RateTable?
}

public final class ExchangeRateService: Sendable {
    func refreshIfNeeded(now: Date, maxAge: TimeInterval, cache: ExchangeRateCache) async
}
```

- On launch: if `cache.load()` is missing or its `asOf` is older than `maxAge`, `GET` the
  endpoint via `URLSession`, decode to `ExchangeRateAPIResponse`, build a `RateTable`,
  `cache.save`. The DTO maps `base_code` → base, `rates` → `[String: Decimal]` (JSONDecoder
  preserves Decimal precision), and `asOf` from `time_last_update_unix` (Unix epoch; falls
  back to parsing `time_last_update_utc` if the unix field is absent — confirmed against the
  live response at implementation time).
- On **any** failure (offline, non-200, `result != "success"`, decode error): keep the
  existing cache, log, and return — never throws to the UI. Fully offline-safe.
- Non-blocking: callers render with `cache.load() ?? SeedRates.table` immediately; the fetch
  just refreshes the cache for the next read.

## Data flow

```
launch → ExchangeRateService.refreshIfNeeded()  ──(success)──► ExchangeRateCache.save(table)
                    │ failure → no-op (keep cache)
consumers (GOL-68/69) → table = cache.load() ?? SeedRates.table → CurrencyConverter(table).convert(...)
```

Resolution order is always **cache → seed**. The pure converter is identical regardless of
which table it got.

## Cross-cutting decisions

- **Refresh cadence:** on app launch, refetch only if cache missing or `asOf > 12h` old (API
  updates daily; 12h is cheap and always current-enough).
- **Rounding/precision:** converter returns unrounded `Decimal`; callers sum unrounded, then
  round once for display to the target currency's `fractionDigits` (avoids accumulation error
  in mixed totals).
- **Staleness:** `isStale(asOf:maxAge:)` + the table's `asOf` let consumers render "rates as
  of <date>". Seed reads as stale by virtue of its old `asOf`.
- **Privacy / ATS:** HTTPS endpoint (ATS-clean); PrivacyInfo/ATS already configured (GOL-51).
  Add a "Rates by ExchangeRate-API" attribution line in Settings (GOL-66's screen) to honour
  the free-tier terms.

## Tests (TDD — written first, GoldengoCore unit tests)

Pure logic is unit-tested; cache + fetcher are verified by build + sim runtime (project
convention). Each test encodes intent (Rule 9):

1. **Identity** — `convert(x, from: EUR, to: EUR) == x` (even on a table missing EUR).
2. **Cross-rate** — USD-base table with known ALL/EUR rates: `convert(100, ALL→EUR)` equals
   the hand-computed `100 * rate[EUR]/rate[ALL]` within epsilon. Encodes "conversion uses the
   correct cross-rate".
3. **Round-trip** — `convert(convert(x, A→B), B→A) ≈ x` within epsilon. Encodes "conversion is
   reversible" (catches inverted ratios).
4. **Missing rate** — `convert(_, from: <code not in table>)` throws `.missingRate(code)`.
   Encodes "we never silently fabricate a rate" (acceptance-critical).
5. **`RateTable` Codable round-trip** — encode→decode preserves base/rates/asOf exactly
   (Decimal precision intact). Encodes "cache survives serialization".
6. **Staleness boundary** — `isStale` is false just under `maxAge`, true just over.
7. **`CurrencyCode` metadata** — `fractionDigits`: JPY=0, KRW=0, ALL=0, BHD=3, EUR=2, USD=2,
   `"ZZZ"`(unknown)=2; `symbol` shortlist + unknown falls back to code. Encodes "ISO 4217
   minor units are honoured".
8. **Seed integrity** — `SeedRates.table` decodes, contains a populated `rates` (incl. ALL &
   EUR), and converts ALL↔EUR without throwing. Encodes "offline/first-run is always usable".

## Runtime verification (before declaring done)

Per the project's runtime-verification rule: build the app for the iPhone 17 sim, launch with
seeded data, capture `os_log` for AttributeGraph cycles / "modifying state" / hangs, and
confirm a real fetch populates the cache (log the fetched `asOf` + a sample converted figure).
Then dispatch a second Opus 4.8 reviewer over the diff and fix findings before merge.

## Out of scope (follow-up tickets)

- GOL-66: preferred/display currency in Settings (consumes this; adds the attribution line).
- GOL-65: Quick-Add per-transaction currency picker (full list from the table + `popular`).
- GOL-68: mixed-currency totals + lek↔euro flip toggle (consumes `CurrencyConverter`).
- GOL-69: currency-aware subscriptions + converted Home estimate.
