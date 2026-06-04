# GOL-77 — Apple Pay auto-log (in-store taps via the Transaction automation)

**Ticket:** [GOL-77](https://mysigner.youtrack.cloud/issue/GOL-77).
**Status:** design approved; pending spec review.
**Date:** 2026-06-04.
**Depends on:** GOL-73 (App Shortcut/Intent in the app target; `ExpenseLogging.log`), GOL-76 (in-app setup-card pattern) — shipped.

## Goal

When the user makes an **in-store Apple Pay payment**, the expense is added to Goldengo
**automatically** — no app launch, no per-payment tap — labeled by merchant and in the user's
currency. Realtime, hands-off, after a one-time setup.

## Decision record (feasibility — researched, see GOL-77 / chat)

- **No private API** lets a third-party app read Apple Pay transaction history (Apple blocks it for
  privacy). **FinanceKit** (the only read-API) is **US/UK App Store + Finance category + Apple
  Card/Cash/Savings (or UK open banking)** — not a global, all-cards path. Rejected as the base.
- **The universal mechanism is iOS 17's "Transaction" Personal Automation:** it fires on an Apple Pay
  tap, can **Run Immediately** (no notification), and hands the **amount** (and merchant) to an
  **action**. This is what every Apple Pay expense tracker uses (TravelSpend, MoneyCoach, MonAi).
- **The one-time setup is unavoidable and ours-to-guide-only.** Apple gives **no API** to create,
  pre-install, or even share a Personal Automation (they're device-specific, don't sync). So Goldengo
  cannot set it up for the user — we provide a guided in-app card and the **action** the automation
  calls. After setup, it's automatic per payment.
- **Reuse the existing logging path.** The intent calls `ExpenseLogging.log` → `logManual`, so it gets
  merchant→category auto-categorization, subscription detection, the preferred currency, and the
  widget today-total refresh for free. No new persistence.
- **In-store/NFC only.** Online/in-app/web Apple Pay does not trigger the automation — statement
  import (existing `GoldengoImport`) remains the catch-all for those. Auto-log OR import for a given
  card, not both (no dedup between the two paths — `logManual` uses a unique key).

## Components

### 1. `LogPaymentIntent` — silent logging action (app target)

Added to the **existing** `AppProject/Goldengo/QuickLogShortcut.swift` (no new app-target file → no
`project.rb` regeneration → signing stays intact). A plain `AppIntent` (not an `AppShortcut`), so it
appears as a **"Log Payment" action** in the Shortcuts action picker when the user builds the
automation:

```swift
@available(iOS 17.0, *)
struct LogPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Payment"
    static let description = IntentDescription("Add a payment to Goldengo — wire this to an Apple Pay Transaction automation.")

    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Merchant") var merchant: String?

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Log a \(\.$amount) payment from \(\.$merchant)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = GoldengoStore.shared()
        let preferred = SharedSummary().readPreferredCurrency()
        var raw = Decimal(amount), amt = Decimal()
        NSDecimalRound(&amt, &raw, preferred.fractionDigits, .plain)   // currency-precise; no float artifacts
        let m = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await ExpenseLogging.log(amount: amt, currencyCode: preferred.rawValue,
                                         merchant: (m?.isEmpty ?? true) ? nil : m, categoryName: nil, store: store)
        return .result()   // silent — the automation runs with no notification
    }
}
```

Passing `merchant` with `categoryName: nil` makes `logManual` set `merchantName` (shown in the Recent
row via `displayTitle`, and fed to subscription detection) and pick the **learned default category
for that merchant, falling back to "Other"** — so auto-logged payments are named and as categorized
as the app's existing mapping allows; the user can recategorize in Edit.

### 2. Settings — "Apple Pay auto-log" setup card (`SettingsView`)

A new `Section` mirroring GOL-76's "Quick-log gesture" card: a short description, an **Open Shortcuts**
button (`openURL("shortcuts://")`), and the exact steps —

1. Shortcuts → **Automation** tab → **＋** → **Create Personal Automation** → **Transaction**.
2. Choose the card(s) (or Any) → **Run Immediately** (turn off "Notify When Run").
3. **Add Action** → search **Log Payment** (Goldengo) → set **Amount** to the transaction's *Amount*
   and **Merchant** to its *Merchant* → **Done**.

Plus the honest note: in-store taps only; online payments use statement import; one-time setup (iOS
won't let an app do it for you).

## Data flow

```
in-store Apple Pay tap → iOS Transaction automation (Run Immediately)
   → Log Payment action (LogPaymentIntent) with Amount (+ Merchant) from the trigger
   → perform(): round to preferred-currency precision → ExpenseLogging.log(merchant:, categoryName: nil)
   → logManual → ExpenseRecord (merchant set, learned/Other category, preferred currency)
      → subscription auto-match + widget today-total refresh
   → silent .result(); app not launched
later: open Goldengo → expense already on Home (scenePhase .active reload from GOL-73)
```

## Tests

- **`ExpenseLogging.log` with a merchant, no category (GoldengoIntentsTests / GoldengoDataTests):** an
  unknown merchant lands in **"Other"** with `merchantName` set; a merchant with a learned mapping
  lands in that category. *Why: auto-captured payments must be labeled and never silently uncategorized
  — they appear in Top Categories and are re-assignable.* (The merchant→category + "Other"-fallback
  logic already lives in `logManual` and is covered by `LogManualTests`/`AutoCategorizeTests`; this
  adds the merchant-set-but-unknown case if not already covered.)
- **Intent + automation (build + device):** the `LogPaymentIntent` shows as a Shortcuts action; a
  Transaction automation wired to it auto-logs a tap with the right amount/merchant/currency, silently,
  no app launch — verified on device (the simulator has no Apple Pay/Transaction trigger). The amount
  rounding is exercised by the device test.

## Runtime verification

Device only. Build + install. The user creates the Transaction automation per the card, taps to pay
in a store, and confirms: the expense appears in Goldengo (correct amount + merchant + currency,
categorized or "Other"), no app launch, no per-payment prompt. Second-Opus review over the diff.

## Out of scope

- **FinanceKit / US-UK automatic read** (separate, entitlement-gated effort).
- **Online / in-app / web Apple Pay** capture (not possible via the automation; use statement import).
- **Dedup between auto-log and statement import** (they don't merge; the card tells the user to pick
  one per card).
- Creating/pre-installing the automation for the user (no iOS API).
- No new `ExpenseSource` case — auto-logged payments reuse the existing `logManual` (`.manual`) path
  for v1.
