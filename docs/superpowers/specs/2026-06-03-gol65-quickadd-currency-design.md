# GOL-65 — Quick Add: per-transaction currency picker + adaptive decimal key

**Ticket:** [GOL-65](https://mysigner.youtrack.cloud/issue/GOL-65) (subtask of epic [GOL-63](https://mysigner.youtrack.cloud/issue/GOL-63), multi-currency).
**Status:** design approved; pending spec review.
**Date:** 2026-06-03.
**Depends on:** GOL-67 (converter/rate table), GOL-66 (`CurrencyPickerView`, `CurrencyCatalog`, preferred-currency default) — both shipped.

## Goal

Let the user choose the currency for the expense being added, from the Quick Add screen, in one
tap and with no extra screen — defaulting to the preferred currency, scaling to all supported
currencies, and persisting the chosen currency on the expense. The keypad's decimal key already
adapts via `QuickAddModel.allowsDecimal`; switching currency must update it live.

## Decision record

- **Tap the currency symbol → quick `Menu`** (chosen over an inline L/€ segment or a full sheet).
  Rationale: the symbol is already shown next to the amount ([QuickAddView.swift:69]), so making it
  tappable adds **no new persistent UI**, keeps the screen minimal, costs no extra screen for the
  common case, and scales to all currencies via a "More…" entry. The segment is fastest for exactly
  two currencies but adds a persistent control and doesn't scale; a sheet-every-time is heavier than
  "no extra screen."
- **Reuse GOL-66's `CurrencyPickerView` + `CurrencyCatalog`** for the "More…" long tail.
- **Sanitize the typed amount when switching to a lower-precision currency** (euro "12.50" → lek
  "12"), preserving the app's existing "display == saved value" invariant.

## Components

### 1. `CurrencyInput` — pure amount sanitizer (GoldengoCore)

Pure and unit-tested; no UI/store dependency:

```swift
public enum CurrencyInput {
    /// Trim a typed amount string so its fractional part fits a currency's minor-unit digits.
    /// Used when switching to a lower-precision currency so display still equals the saved value.
    public static func fit(_ amountString: String, toFractionDigits digits: Int) -> String {
        guard let dot = amountString.firstIndex(of: ".") else { return amountString }
        if digits == 0 { return String(amountString[..<dot]) }            // drop "." + fractional digits
        let fracStart = amountString.index(after: dot)
        let fracCount = amountString.distance(from: fracStart, to: amountString.endIndex)
        guard fracCount > digits else { return amountString }
        return String(amountString[..<amountString.index(fracStart, offsetBy: digits)])
    }
}
```

### 2. `QuickAddModel.setCurrency(_:)` (GoldengoFeatures)

A single entry point that switches currency and keeps the typed amount valid:

```swift
public func setCurrency(_ code: CurrencyCode) {
    currency = code
    amountString = CurrencyInput.fit(amountString, toFractionDigits: code.fractionDigits)
}
```

`currency` and `amountString` are already observed, so the symbol, the keypad ("." key via
`allowsDecimal`), and the amount display update live. `save()` already passes `currency` to
`store.logManual(currency:)`, so the choice persists on the expense (no change needed).

### 3. Quick Add currency `Menu` + "More…" sheet (GoldengoFeatures, `QuickAddView`)

Replace the static symbol in `amountDisplay` with a `Menu` whose label is the symbol plus a small
`chevron.down` affordance (kept subtle; the amount stays the hero, baseline-aligned):

- **Menu items:** the common currencies — `CurrencyCode.popular` intersected with the available
  set, with the current currency ensured present and shown with a checkmark — each a `Button` that
  calls `model.setCurrency(_:)`. A `Divider`, then **"More currencies…"** which sets
  `showCurrencyPicker = true`.
- **Item label:** `"<symbol>  <localized name>"` via `Locale.current.localizedString(forCurrencyCode:)`.
- **"More…" sheet:** `.sheet(isPresented: $showCurrencyPicker)` presenting
  `NavigationStack { CurrencyPickerView(available:selectedCode:) }`, where `selectedCode` is a
  `Binding<String>` bridging `model.currency.rawValue` ↔ `model.setCurrency(CurrencyCode($0))`. The
  picker's `dismiss()` closes the sheet on selection (it pops in Settings, dismisses the sheet here —
  presentation-agnostic).
- **Available set:** `CurrencyCatalog.selectable(from: ExchangeRateCache().load() ?? SeedRates.table)`
  (same source Settings uses). `QuickAddView` adds `import GoldengoCore` + `import GoldengoData`.

`CurrencyPickerView` stays where it is (internal to GoldengoFeatures, reused by Settings + Quick Add);
a doc comment notes the shared use.

## Data flow

```
Quick Add opens with model.currency = preferred (wired in GOL-66)
tap symbol → Menu → pick common currency  → model.setCurrency(c)  → symbol + "." key + amount adapt
                  → "More currencies…" → sheet picker → setCurrency → sheet dismisses
Add expense → store.logManual(currency: model.currency)  (already wired; choice persists)
```

## Tests

- **`CurrencyInput` (GoldengoCoreTests):** `fit("12.50", 0) == "12"` (euro→lek truncates);
  `fit("12.50", 2) == "12.50"` (no-op same precision); `fit("1.234", 2) == "1.23"` (trims to 2);
  `fit("12", 0) == "12"` and `fit("12", 2) == "12"` (no decimal, unchanged); `fit("0.99", 0) == "0"`.
  Encodes "switching to a lower-precision currency keeps display == the saved value."
- **`QuickAddModel.setCurrency` (GoldengoFeaturesTests) — if a `QuickAddModel` is cheaply
  constructible in tests** (in-memory `IngestionStore`): assert switching euro→lek both sets
  `currency` and trims a typed "12.50" to "12", and that `allowsDecimal` flips. If construction is
  heavy, rely on the pure `CurrencyInput` test (the delegation is two lines) and runtime.
- **UI (build + runtime):** sim build + screenshot showing the new symbol+chevron affordance;
  device tap-test (menu open, switch a common currency, "More…" → search/pick) since the menu/sheet
  need real taps.

## Runtime verification

Sim with seeded data: screenshot Quick Add showing the symbol+chevron affordance; confirm the build
runs and (set preferred euro via `defaults write`, relaunch) the symbol + "." key reflect it. Capture
os_log for AttributeGraph cycles / "modifying state" / hangs. Device: tap the symbol → menu → switch
lek↔euro and via "More…", confirm the amount sanitizes and the chosen currency saves on the expense.
Then a second-Opus reviewer over the diff; fix findings.

## Out of scope (follow-ups)

- GOL-68: mixed-currency dashboard totals + lek↔euro flip toggle (conversion via `CurrencyConverter`).
- GOL-69: currency-aware subscriptions + converted Home estimate.
- "Recently used" currency ordering in the menu (YAGNI for now; the popular set is the proxy).
