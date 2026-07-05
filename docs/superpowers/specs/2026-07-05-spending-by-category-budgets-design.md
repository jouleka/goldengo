# Spending by category + budgets — design

Date: 2026-07-05
Status: approved design, pending spec review

## Goal

Give the user a clear, ongoing answer to "how much is each category taking from me?"
(food, groceries, cigarettes, …) for a chosen month, and let them set a monthly cap
per category with in-app progress and an overspend push notification.

Reached by tapping the top-categories block that already exists on the Home dashboard —
a screen pushed from Home, not a new tab.

## Non-goals (deliberately deferred)

- Per-month budget overrides (v1 uses one recurring monthly cap per category).
- Budget rollover / carryover.
- Income or savings budgeting.
- Server-driven / remote push. Overspend detection runs in-process; a crossing that
  happens while the app is fully closed surfaces on next app-active, not before.
  This is an accepted limitation of a local-notification (no backend) approach.

## What already exists (reused, not rebuilt)

- `ExpenseRecord` (`Sources/GoldengoData/Models/ExpenseRecord.swift`): `amount: Decimal`,
  `currencyCode`, `date`, `category: CategoryRecord?`, `kindRaw`, `isArchived`.
- `CategoryRecord` (`Sources/GoldengoData/Models/CategoryRecord.swift`): `name`, `icon`,
  `colorHex`. Uncategorized spend falls back to the `"Other"` bucket.
- `CategoryTotal { name, total }` and the dashboard aggregation in
  `IngestionStore+Dashboard.swift` — groups by `category?.name ?? "Other"`, sums
  converted amounts in memory. This is the exact pattern we extend.
- Currency conversion via `CurrencyConverter` + `RateTable`.
- Local-notification scheduler, delegate, permission request, and actionable-notification
  category registration used by loan/subscription reminders
  (`Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift`,
  `AppProject/Goldengo/GoldengoApp.swift`).
- `IngestionStore` is a `@ModelActor` actor; its save choke point is in `logEntry(...)`
  and `ingest(...)` right after `try modelContext.save()`.
- `RootView` (`Sources/GoldengoFeatures/RootView.swift`) already re-checks state on
  `.task` (cold launch) and `scenePhase == .active` (foreground return), reloading Home
  because an expense may have been logged via the Quick-Log shortcut while backgrounded.

## Architecture — where each piece lives

Module layering is a hard constraint: `GoldengoData` must not depend on
`GoldengoFeatures`. Therefore:

- Data layer (`GoldengoData`) owns **computation and dedupe state**: the breakdown, the
  per-category budget level, and "which alerts newly escalated." Pure and testable. No
  `UserNotifications` import here (keeps the existing separation intact).
- Feature layer (`GoldengoFeatures`) owns **firing**: on the `RootView` lifecycle hook it
  asks the data layer to evaluate budgets, then hands any returned alerts to the existing
  notification scheduler. This is the one trigger point that catches every ingestion
  source (in-app, Quick-Log intent, statement import) uniformly.

Rule split, restated: **in-app red/amber state is live UI derived from data (never
deduped); the push is a discrete event fired on lifecycle, deduped once per
(category, month, level).**

## Data model changes

Add to `CategoryRecord` (all optional / defaulted → lightweight SwiftData migration):

```swift
public var monthlyBudget: Decimal?          // nil = no cap. In the user's display currency.
public var budgetAlertLevelRaw: String = "none"   // last level we PUSHED at: none | near | over
public var budgetAlertMonth: Date?          // start-of-month the pushed level applies to
```

Notes:
- `monthlyBudget` is a plain amount interpreted in the current display currency. Changing
  the display currency later does not convert existing caps (known, acceptable limitation).
- The two `budgetAlert*` fields exist only to dedupe pushes; they are never shown in the UI.
- `Decimal` is compared **in memory only** — never inside a `#Predicate` (segfault landmine).

## Computation (GoldengoData, extends the dashboard pattern)

### Breakdown for the screen

```swift
public struct CategoryBreakdownRow: Sendable, Equatable, Identifiable {
    public var name: String
    public var icon: String
    public var colorHex: String
    public var spent: Decimal
    public var budget: Decimal?
    public var share: Double          // 0…1 of period total
    public var level: BudgetLevel     // ok | near | over | noBudget
    public var id: String { name }
}

public enum BudgetLevel: String, Sendable { case ok, near, over, noBudget }

public struct CategoryBreakdown: Sendable, Equatable {
    public var month: PeriodRange
    public var total: Decimal
    public var rows: [CategoryBreakdownRow]   // sorted by spent desc, then name
    public var currencyCode: String
    public var ratesAsOf: Date?
}
```

`makeCategoryBreakdown(month:displayCurrency:)`:
1. Fetch the month's records with a **date-only** `#Predicate`
   (`isArchived == false && date >= start && date < end`); prefetch `\.category`.
2. Keep only `kind == .expense` (income, transfer, lent, repayment never count as spend).
3. Group by `category?.name ?? "Other"`, summing converted amounts in memory.
4. Attach each category's `icon`, `colorHex`, `budget`; compute `share` and `level`.

### Budget levels (thresholds)

- `noBudget` — `monthlyBudget == nil`.
- `ok` — spent < 85% of cap.
- `near` — 85% ≤ spent < 100%.
- `over` — spent ≥ 100%.

`85%` (the "near" line) is a single named constant, fixed in v1.

### Alert evaluation + dedupe

```swift
public struct BudgetAlert: Sendable, Equatable {
    public var categoryName: String
    public var level: BudgetLevel     // near or over
    public var spent: Decimal
    public var budget: Decimal
    public var currencyCode: String
}

public func evaluateBudgetAlerts(asOf: Date, displayCurrency: CurrencyCode) throws -> [BudgetAlert]
```

For the current month, for each category with a cap:
- Compute the current `level`.
- Compare against the stored `(budgetAlertLevelRaw, budgetAlertMonth)`:
  - New month → treat stored level as `none` (reset).
  - Escalation only (`none → near`, `none → over`, `near → over`) produces a `BudgetAlert`
    and updates the stored level + month.
  - De-escalation (e.g. a refund drops spend) does **not** notify and does **not** lower
    the stored level within the month — monotonic per month, so a boundary wobble can't
    spam. It resets next month.
- Returns the alerts that newly escalated. Idempotent: calling it again the same month
  with no new escalation returns `[]`.

## Notification firing (GoldengoFeatures)

- A small overspend firing function alongside the existing reminder scheduler. It reuses
  the existing `UNUserNotificationCenter`, the shared delegate, permission state, and
  category-registration block, with a **distinct identifier prefix** `"overspend:"`.
- Trigger is **immediate** (event-driven), unlike the reminders' 09:00 calendar trigger:
  a crossing warrants a prompt heads-up, not a next-morning one.
- Copy is plain and specific, e.g. over → title "Over budget on Cigarettes",
  body "You've spent ALL 12,600 of your ALL 10,000 cap this month." near → "Close to your
  Groceries cap — ALL 2,000 left this month." (sentence case, no exclamation.)
- Tapping routes into the breakdown screen (optionally focused on that category). Reuse the
  existing delegate; add an `"overspend:"` branch. No custom actions in v1 (body tap only).
- Permission: reuse `requestAuthorization()`, called once at the natural opt-in moment —
  when the user sets their first budget cap. The existing `isRunningTests` guard keeps
  tests from prompting.

Wiring: in `RootView` `.task` and `scenePhase == .active`, call
`store.evaluateBudgetAlerts(...)` and fire the returned alerts. Because firing is driven
here (not from the data save path), in-app manual logs show the live red/amber state
instantly and the push arrives on the next app-active — deduped, so never doubled.

## UI (GoldengoFeatures, built with the frontend-design skill)

Match the on-`main` `GoldengoTheme` (warm bone + gold) and existing components
(`goldengoCard()`, `GoldengoIconTile`, the shared expense rows). Get it on the user's
device early as the go/no-go — green tests are not sign-off on the look.

### Entry point
The existing Home top-categories block becomes tappable → pushes `CategoryBreakdownView`.

### CategoryBreakdownView
- Month stepper header (`‹ July 2026 ›`) stepping through months; the period total below.
  Reuse `PeriodScale.month` navigation.
- A donut with the period total in the center (Swift Charts `SectorMark`, iOS 17+),
  segment color = category `colorHex`.
- Ranked category rows (spent desc): color dot, name, amount, share %. If a cap is set, a
  progress bar tinted by level (green `ok` / gold `near` / terracotta `over`) with a caption
  ("5,500 left" / "over by 2,600").
- Tap a category row → its expenses for that month (reuse the shared expense rows).
- Tap **Other** → the month's uncategorized expenses, each with a quick assign-category
  action (reuse the QuickAdd category input / create-on-demand). This is how "Cigarettes"
  becomes its own line and how the breakdown improves the data instead of just displaying it.

### Setting a cap
Tap a category's budget area (or the header edit affordance) → a minimal number field to set
`monthlyBudget`. Keyboard dismissal per house rule: tap-outside / Return / focus-clear —
never a keyboard "Done" toolbar. Setting the first cap triggers the permission request.

### Home surfacing
When any capped category is `over` for the current month, show a small terracotta dot on the
Home top-categories block (live, derived from the breakdown — no extra state).

## Testing (Rule 9 — encode why, not just what)

Data-layer tests (`GoldengoDataTests`, following existing SwiftData test conventions):
- Grouping: expenses roll up by `category?.name`; uncategorized land in `"Other"`.
- Exclusions: `transfer`, `lent`, `repayment`, `income`, and `isArchived` records never
  count toward spend or a cap (a transfer must not eat someone's food budget).
- Multi-currency: mixed-currency expenses sum correctly in the display currency.
- Level thresholds: `ok`/`near`/`over` flip at exactly < 85%, ≥ 85%, ≥ 100% of cap.
- Dedupe: escalation fires once (`none→near→over` = two alerts); repeat evaluation the same
  month yields none; a new month re-arms; a mid-month refund (de-escalation) fires nothing
  and doesn't lower the stored level.
- `Decimal` handled only in memory (no `#Predicate` comparison) — guards the segfault.

Keep these tests synchronous where the target links AppIntents; `GoldengoDataTests` does not,
so async is fine there (per the AppIntents async-XCTest note).

## Risks / open items

- Confirm the exact scheduler type name/signature in `SubscriptionReminders.swift` at
  implementation time (the map referenced both `SubscriptionReminders` and a
  `LocalNotificationScheduler`); reuse whichever is the real seam.
- Confirm whether a standalone category picker exists to reuse for "assign from Other," or
  whether a minimal one is needed.
- SwiftData migration for the three new optional `CategoryRecord` fields should be additive
  (defaulted) — verify no manual migration plan is required.
