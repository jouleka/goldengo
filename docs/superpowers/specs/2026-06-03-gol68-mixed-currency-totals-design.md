# GOL-68 — Mixed-currency totals + display-currency control

**Ticket:** [GOL-68](https://mysigner.youtrack.cloud/issue/GOL-68) (subtask of epic [GOL-63](https://mysigner.youtrack.cloud/issue/GOL-63)).
**Status:** design approved; pending spec review.
**Date:** 2026-06-03.
**Depends on:** GOL-67 (`CurrencyConverter` + rate cache/seed), GOL-66 (preferred currency) — shipped.

## Goal

Make every Home/widget total **sum mixed-currency expenses** by converting each to one display
currency (the user's default), so lek + euro + USD roll into one real number instead of `€ 0.00`.
The default currency is set in Settings (GOL-66) and changeable from the dashboard; changing it
reconverts everything. Show FX staleness subtly. Recent rows keep each expense in its own currency.

## Decision record

- **One default currency (unified).** Per the user: "have a default currency you can set, everything
  is calculated in that, and you can change that default." The display currency **is** the preferred
  currency (GOL-66) — no separate concept. Per-transaction adds still override via the Quick Add
  picker (GOL-65).
- **Convert, don't filter.** Aggregation converts each expense to the display currency via the rate
  table (`cache ?? seed`, offline-safe) instead of filtering to one `currencyCode`.
- **Changeable from the dashboard too.** The currency on the "This month" total is a tappable control
  (same menu idiom as Quick Add) that changes the default currency and reconverts. Still changeable
  in Settings.
- **Staleness shown only when it matters:** a subtle "Rates as of <date>" caption appears under the
  total only when conversion actually happened (mixed currencies present).
- **Missing rate → skip that expense** (the seed carries 162 currencies, so this is a near-impossible
  safety net, not an expected path).

## Components

### 1. `CurrencyConverter.sum(_:to:)` — pure (GoldengoCore)

Convert a list of `Money` to a target currency and sum, skipping any that can't convert:

```swift
public func sum(_ monies: [Money], to target: CurrencyCode) -> Decimal {
    monies.reduce(Decimal(0)) { acc, m in
        (try? convert(m, to: target)).map { acc + $0.amount } ?? acc
    }
}
```

Pure and unit-tested. (Same-currency items convert via identity, so single-currency sums are exact.)

### 2. Conversion in aggregation (GoldengoData)

`IngestionStore+Dashboard` and `todayTotal` stop filtering by currency and instead convert. The rate
table crosses the actor boundary as a `Sendable` value:

- `todayTotal(in displayCurrency: CurrencyCode, rates: RateTable) -> Decimal` — fetch today's
  expenses (all currencies), map to `[Money]`, `CurrencyConverter(table: rates).sum(_, to: displayCurrency)`.
- `dashboardSummary(in displayCurrency: CurrencyCode, rates: RateTable, now:, topCategoryLimit:)` —
  fetch the month's expenses (all currencies); `monthTotal` and each category total are converted
  sums; `confirmedSubscriptionsMonthly` converts each confirmed sub's monthly-equivalent. The
  `RecentExpensesReading` protocol methods gain the `rates:` parameter (and the test fakes are
  updated).
- `DashboardSummary` gains `ratesAsOf: Date?` — set to `rates.asOf` when any expense needed
  conversion (a non-display currency was present), else `nil`. `currencyCode` now means
  "converted into this currency."

### 3. `RecentExpensesModel` (GoldengoFeatures)

`load()` loads the rate table (`ExchangeRateCache().load() ?? SeedRates.table`) and passes it to the
reader. Exposes `ratesAsOf: Date?` (from the summary) for the staleness caption. `monthTotalText()`,
`todayTotalText`, `categoryTotalText()` already format in `currency` — now that currency is the
display currency and the underlying figures are pre-converted, so they need no formatting change.

### 4. Widget today total (GoldengoData, `IngestionStore`)

The two writes that currently hardcode lek — `IngestionStore.swift:125-126` (`logManual`) and
`:158-159` (`importStatement`) — are replaced by a private helper:

```swift
private func refreshSharedTodayTotal() throws {
    let display = SharedSummary().readPreferredCurrency()
    let rates = ExchangeRateCache().load() ?? SeedRates.table
    let total = try todayTotal(in: display, rates: rates)
    SharedSummary().writeTodayTotal(Money(amount: total, currency: display).formatted())
}
```

So the widget reflects the converted today total in the default currency. (No widget-target code
change; it already reads the shared string.)

### 5. Dashboard display-currency control + staleness (GoldengoFeatures, `RecentExpensesView`)

- The "This month" total renders the currency as a **tappable menu** (the Quick Add idiom: common
  currencies + "More…" → the reused `CurrencyPickerView`). Selecting one changes the default
  currency. To keep one source of truth and update Quick Add too, the view calls a new
  `onChangeCurrency: (CurrencyCode) -> Void` closure that `RootView` implements:
  `SharedSummary().setPreferredCurrency(_)`, set `recentModel.currency` + `quickAddModel.currency`,
  reload Home (mirrors the existing Settings-dismiss logic).
- A subtle caption — `Text("Rates as of \(date)")`, `.caption2`, `.secondary` — appears under the
  total only when `model.ratesAsOf != nil`.

## Data flow

```
default currency = preferred (Settings or dashboard menu) → recentModel.currency + quickAddModel.currency
RecentExpensesModel.load → rates = cache ?? seed → reader.dashboardSummary(in: display, rates:)
   → each expense converted to display currency, summed → monthTotal/today/categories/subs in display currency
   → ratesAsOf set if any conversion happened
mutations (logManual/import) → refreshSharedTodayTotal() → widget shows converted today total
Recent rows: unchanged (each expense in its own currency)
```

## Tests

- **`CurrencyConverter.sum` (GoldengoCoreTests):** sum `[L100, €1, $1]` to EUR with a known table
  equals the hand-computed converted sum; same-currency-only sum is exact; an un-convertible entry is
  skipped (others still counted). Encodes "totals add up across currencies."
- **`dashboardSummary`/`todayTotal` conversion (GoldengoDataTests, in-memory store):** log lek + euro
  + USD expenses; with a fixed `RateTable`, assert `monthTotal` and `todayTotal` equal the converted
  sum in the display currency, that flipping the display currency reconverts, and that `ratesAsOf` is
  set when mixed (nil when single-currency). Extends `DashboardSummaryTests`.
- **Widget total:** after `logManual`, `SharedSummary().read().todayTotalText` is the converted total
  in the preferred currency (in-memory store + a seeded preferred + rate table).
- **UI (build + runtime):** sim with mixed lek/euro/USD seeded data — the month/today/category totals
  are non-zero and correct in the display currency; the "Rates as of" caption shows; device tap-test
  of the dashboard currency menu (changing it reconverts everything).

## Runtime verification

Sim with mixed-currency data: screenshot Home showing a correct converted total (not 0) + the
staleness caption; flip the display currency via the menu and confirm everything reconverts; confirm
the widget string updates. Capture os_log for AttributeGraph cycles / "modifying state" / hangs. Then
a second-Opus review over the diff; fix findings. Device install for the user to confirm the tap-flow.

## Out of scope (follow-up)

- GOL-69: the Subscriptions **tab** detecting/displaying euro-billed subs in euro. (The Home
  subscriptions "~/mo" estimate converts here, since it sits under the total.)
