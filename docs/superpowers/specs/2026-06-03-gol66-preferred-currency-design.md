# GOL-66 — Preferred / display currency setting

**Ticket:** [GOL-66](https://mysigner.youtrack.cloud/issue/GOL-66) (subtask of epic [GOL-63](https://mysigner.youtrack.cloud/issue/GOL-63), multi-currency).
**Status:** design approved; pending spec review.
**Date:** 2026-06-03.
**Depends on:** GOL-67 (the `CurrencyConverter` + rate cache/seed) — shipped.

## Goal

Let the user pick a **preferred currency** in Settings, persisted via the App-Group/UserDefaults
pattern other settings use. It drives (a) the Quick Add default currency and (b) the dashboard's
default display currency. Keep it minimal and intuitive — the everyday pick (lek/euro/USD) is one
tap; every market stays reachable.

This ticket ships **only**: the persisted setting, the Settings picker UI, the pure search filter,
and the single-currency wiring into Quick Add + the dashboard. It does **not** add mixed-currency
conversion or the lek↔euro flip toggle (that is GOL-68), nor the per-transaction Quick Add picker
(GOL-65).

## Decision record

- **Picker UX: searchable list with a "Suggested" group** (chosen over a curated short list or an
  inline menu). Rationale: the only option that satisfies all of the app's constraints at once —
  the common pick is one tap with no scrolling, every currency stays reachable via search, and it's
  a pattern users already know. A curated-only list would "close off markets"; an inline menu is
  clunky and search-less at ~160 entries.
- **Currency names come from Foundation** (`Locale.current.localizedString(forCurrencyCode:)`) —
  localized, zero hardcoding of ~160 names.
- **Picker universe = the currencies we have rates for** (`cache ?? seed`), so every selectable
  currency is guaranteed convertible. Obvious non-currencies (precious-metal codes XAU/XAG/XPD/XPT,
  XDR) are excluded from the picker *if present* in the table — they aren't spendable currencies.
- **Default = lek (`ALL`)** — the user's home currency.

## Components

### 1. `SharedSummary` — persisted preferred currency (GoldengoData)

Add to the existing App-Group `UserDefaults` wrapper (mirrors `revealKey`/`remindBeforeChargesKey`):

```swift
import GoldengoCore   // new: SharedSummary needs CurrencyCode
// ...
public static let preferredCurrencyKey = "preferredCurrency"   // stores the ISO code string

public func readPreferredCurrency() -> CurrencyCode {
    let raw = defaults.string(forKey: Self.preferredCurrencyKey) ?? ""
    return raw.isEmpty ? .all : CurrencyCode(raw)
}
public func setPreferredCurrency(_ code: CurrencyCode) {
    defaults.set(code.rawValue, forKey: Self.preferredCurrencyKey)
}
```

The Settings view binds to the same key via `@AppStorage` (String) for a live UI; `RootView`
reads the typed value via `readPreferredCurrency()`.

### 2. `CurrencyCatalog` — pure helpers (GoldengoCore)

Pure, unit-tested. No `Locale`/UI dependency (the name lookup is injected so it stays testable):

```swift
public enum CurrencyCatalog {
    /// Codes excluded from the picker — not spendable everyday currencies.
    public static let nonCurrencyCodes: Set<String> = ["XAU", "XAG", "XPD", "XPT", "XDR"]

    /// The selectable universe from a rate table: every rate code minus non-currencies.
    public static func selectable(from table: RateTable) -> [CurrencyCode] {
        table.rates.keys
            .filter { !nonCurrencyCodes.contains($0) }
            .map(CurrencyCode.init)
    }

    /// Case-insensitive filter by ISO code OR display name. Empty query → unchanged input.
    public static func filter(_ codes: [CurrencyCode], query: String,
                              name: (CurrencyCode) -> String) -> [CurrencyCode] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return codes }
        return codes.filter { $0.rawValue.lowercased().contains(q) || name($0).lowercased().contains(q) }
    }
}
```

### 3. `CurrencyPickerView` — searchable picker (GoldengoFeatures)

A `View` presented from Settings:
- Inputs: `available: [CurrencyCode]` (from `CurrencyCatalog.selectable`) and
  `@Binding var selectedCode: String` (bound to the Settings `@AppStorage` on
  `preferredCurrencyKey`, so a tap persists immediately to the App Group).
- `.searchable(text:)`. When the query is empty: two sections — **Suggested** (`CurrencyCode.popular`
  intersected with `available`, order preserved) and **All** (the rest, sorted by localized name).
  When searching: one flat `CurrencyCatalog.filter(...)` result.
- Row: leading symbol, localized name (`Locale.current.localizedString(forCurrencyCode:)` — fall back
  to the code), trailing ISO code; a checkmark on the selected row. Tap → set selection → dismiss.
- Matches `GoldengoTheme`; built with the `/frontend-design` skill for a minimal, on-theme control.

### 4. `SettingsView` — Currency section (GoldengoFeatures)

Add a `Section("Currency")` with a `NavigationLink` to `CurrencyPickerView`, the row trailing-value
showing the current selection (symbol + localized name, e.g. *L · Albanian Lek*). Uses
`@AppStorage(SharedSummary.preferredCurrencyKey, store: appGroup)` (default `"ALL"`).

### 5. `RootView` — read + propagate (GoldengoFeatures)

- When constructing `QuickAddModel` and `RecentExpensesModel`, pass
  `SharedSummary().readPreferredCurrency()` instead of the literal `.all`.
- On Settings-sheet dismissal, re-read the preferred currency; if it changed, update
  `quickAddModel.currency` + `recentModel.currency` and reload the dashboard (reuses the existing
  tab-return / sheet-dismiss refresh path).

## Data flow

```
Settings picker → writes ISO code to App-Group UserDefaults (preferredCurrencyKey)
   │ on Settings dismiss
RootView.readPreferredCurrency() → QuickAddModel.currency (new-expense default)
                                 → RecentExpensesModel.currency (dashboard display currency) → reload
Quick Add opens with currency = preferred (keypad decimal key adapts via allowsDecimal)
```

## Scoping note (Rule 7 — surfaced, not blended)

GOL-66 wires the preferred currency into the dashboard's *display currency*, but the dashboard is
still single-currency until GOL-68 adds conversion + the flip toggle. With the default (lek) this is
exactly today's behaviour. If the user selected a non-lek currency *before* GOL-68 ships, the
dashboard would sum only that currency's expenses (existing single-currency limitation) until
conversion lands. GOL-68 is the immediate next ticket, so the window is brief. Documented as a
conscious sequencing choice.

## Tests

- **`SharedSummary` (GoldengoDataTests, dedicated suite):** default is `.all` when unset;
  `setPreferredCurrency`/`readPreferredCurrency` round-trips; persists across a fresh
  `SharedSummary` instance on the same suite. Encodes "the preference survives launches."
- **`CurrencyCatalog` (GoldengoCoreTests):** `filter` — empty query returns input unchanged; matches
  by ISO code; matches by injected name; case-insensitive; non-matching → empty. `selectable` —
  excludes the non-currency codes, keeps the rest. Encodes "search finds a currency by code or name,
  and we never offer a non-currency."
- **UI (build + runtime):** sim build + screenshot of the Settings row + picker (Suggested group,
  search), and a tap-test on the paired iPhone (the sim can't drive taps) to confirm selecting a
  currency persists and changes the Quick Add default.

## Runtime verification

Sim with seeded data: open Settings → Currency, screenshot the picker, change the default, confirm
Quick Add opens in the new currency and the value persists across relaunch (read the App-Group
plist key, as in GOL-67). Capture os_log for AttributeGraph cycles / "modifying state" / hangs.
Then a second-Opus reviewer over the diff; fix findings.

## Out of scope (follow-ups)

- GOL-65: Quick Add per-transaction currency picker (one-tap L/€ near the amount).
- GOL-68: mixed-currency dashboard totals + lek↔euro flip toggle (consumes `CurrencyConverter`).
- GOL-69: currency-aware subscriptions + converted Home estimate.
