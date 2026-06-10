# Subscription auto-settle — quiet books-keeping for confirmed subscriptions

**Status:** design approved; pending spec review.
**Date:** 2026-06-10.
**Origin:** the GOL-84 fast-follow ("offer gap-due recurring charges on Re-entry"), resolved by *rejecting* the Re-entry placement and solving the underlying problem instead.
**Builds on:** `SubscriptionDetector`/`SubscriptionRecord` (GOL-81 era), `logAutomatic` + the auto-logged marker (GOL-77/87), GOL-79 import reconciliation, `RootView` scenePhase wiring.

## Goal

Confirmed, fixed-amount subscriptions get their charges logged by Goldengo itself when they fall due — dated at the due date, visibly marked auto-logged, ordinary editable/deletable expenses. Whether you were away ten days or using the app daily, totals and source balances are already right; nothing waits for you.

## Decision record (brainstorm)

- **Re-entry stays untouched.** Any list of missed charges on the warm screen is homework, however gently worded — exactly what the GOL-84 decision record rejected. The deepest form of "nothing's assumed — here's today" is books that are already correct.
- **Reframe:** gap-due charges aren't a Re-entry problem. Subscriptions go unlogged even with daily use (nobody hand-logs Netflix); a gap only widens the existing hole. So the fix is ambient, not gap-triggered.
- **Confirmed = consent** (chosen over a global Settings toggle and per-sub toggles). "Yes, it's a subscription" means Goldengo keeps its books. No new UI; entries carry the existing creditcard + repeat markers and are deletable.
- **`.automatic` source is load-bearing:** it is the only source the GOL-79 reconciliation merges an imported statement row into (`reconcileImportedAgainstAutomatic`, manual entries are never merged — `test_neverMergesIntoManual`). The reconcile window `[postingDay − 4, postingDay + 1)` accepts an entry up to 4 days *before* the posting — exactly the auto-settle case (entry at due date, bank posting trails 0–4 days). **No dedup changes needed.**
- **60-day horizon** (tunable constant): misses within ~2 monthly cycles are near-certainly real; older misses suggest a sub cancelled outside the app — don't fabricate deep history. An eventual statement import can still bring the truth (and merges or inserts per existing rules).
- **Idempotency is derived, not stored:** `nextChargeDate` stays detector-owned — the sweep never reads or writes it (the detector always advances it past `now`, so it cannot represent "missed").

## Revision after adversarial review (same day)

The v1 sweep anchored on "most recent non-archived charge at merchant+currency" and was proven unsafe (empirically, with scratch tests): deleting an auto-settled entry rolled the anchor back so the entry **resurrected on the next foreground**, and a sub cancelled outside the app **fabricated charges indefinitely** (each fabrication became the new anchor and kept the detector series alive). A same-merchant one-off purchase could also hijack the schedule, and the month-end "no drift" property only held within a single run. Revised semantics:

- **Settle entries are identifiable forever:** the sweep logs with dedupeKey prefix `settle:` (vs `auto:` for Apple Pay captures).
- **Schedule anchors only on real evidence:** the most recent non-archived, non-`settle:` charge whose amount is within the detector's `amountTolerance` (15%) of the sub's amount. Sweep output never anchors the schedule, so due dates are always `advance(realAnchor, by: k)` — month-end days never drift across runs, and a gift-card one-off (different amount) can't hijack the schedule.
- **Coverage, not anchoring, dedupes:** a due date is skipped when ANY charge row — live or tombstoned, any source — sits within ±3 days (`coverageWindowDays`). Tombstones count, so **deletion is final**: neither a deleted settle entry nor a deleted real charge is ever recreated.
- **Deletion mutes the sub:** an *archived* `settle:` entry dated at-or-after the real anchor means the user rejected a guess — the sweep skips that sub until newer real evidence arrives. This is the cancellation signal v1 lacked; a dead sub fabricates at most until the user deletes one entry.
- **Ambiguity guard:** two confirmed records sharing merchant+currency (e.g. the series changed cadence over time) → settle neither; don't guess between competing schedules.
- **Reconcile window widened for settle entries only:** an imported posting accepts a `settle:` entry within `[postingDay − 4, postingDay + 4)` (v1's `[−4, +1)` missed real charges that post 1–3 days *before* the predicted date — e.g. 30-day billers vs calendar-month advance — duplicating every cycle). Apple Pay (`auto:`) behavior is unchanged.
- **One bulk fetch** per sweep (early-exit when no eligible subs) instead of a per-sub table scan.
- **Settle on confirm:** `SubscriptionsModel.confirm` triggers a sweep so charges due at confirm time appear immediately, not at the next foreground.

Known accepted limitations: a price change within the 15% tolerance still settles at the sub's (detector-median) amount until the median catches up — the exact-amount reconcile may keep an early posting separate for a cycle or two; same-day double when a foreground sweep fires between midnight and an Apple Pay capture of the same charge (rare, visible, deletable, and a later import merges into one of them).

## Components

### 1. `SubscriptionSettlementPlanner` — pure (GoldengoCore)

```swift
public enum SubscriptionSettlementPlanner {
    public static let horizonDays = 60
    /// Charge dates that fell due after `lastCharge` and at-or-before `now`,
    /// limited to the trailing `horizonDays`. Empty when nothing is due.
    public static func dueCharges(lastCharge: Date, cadence: SubscriptionCadence,
                                  now: Date = .now, calendar: Calendar) -> [Date]
}
```

Walk `cadence.advance(lastCharge)` forward (calendar-accurate, like the detector); collect dates `<= now`; drop any older than `now − horizonDays`. Non-positive/backwards gaps yield `[]`.

### 2. `IngestionStore.settleDueSubscriptionCharges(now:)` (GoldengoData, IngestionStore+Subscriptions)

```swift
/// Logs due-but-unlogged charges for confirmed fixed-amount subscriptions.
/// Returns the number of entries created. Idempotent.
@discardableResult
public func settleDueSubscriptionCharges(now: Date = .now) throws -> Int
```

For each `SubscriptionRecord` with `isConfirmed && !isDismissed && !isArchived && !isVariableAmount`:
1. Fetch the most recent non-archived expense-kind charge for its `normalizedMerchant` + `currencyCode` (same matching as `currentChargeCount`; merchant + Decimal comparisons in memory, never in a `#Predicate`). No observed charge → skip (refresh archives those anyway).
2. `dueCharges(lastCharge:cadence:now:)` → for each date, insert via the existing `logEntry` path: `amount = rec.amount`, `currency = rec.currencyCode`, **`merchantName` copied from the last observed charge** (guarantees `MerchantNormalizer` equality with future statement rows — `displayName` doesn't), `source: .automatic`, `date:` = the due date, no funding pin (automatic FIFO — money really left, sources drain). Category falls out of `logEntry`'s merchant-default lookup; `linkToConfirmedSubscription` attaches it to the sub.
3. One `save()` per sweep.

Requires threading the existing `date:`/`keyPrefix:` parameters of `logEntry` through (private, same file); the public `logAutomatic` signature is unchanged.

### 3. `RootView` wiring (GoldengoFeatures)

On `scenePhase == .active`, call `settleDueSubscriptionCharges()` **before** the dashboard reload so Home wakes already correct. Idempotent, so repeated `.active` in one session is harmless. Ordering relative to the Re-entry check doesn't matter — they don't interact.

## Data flow

```
app foregrounded (.active)
  → for each confirmed fixed-amount sub:
      last observed charge → planner → due dates within 60d
      → .automatic entries dated at due dates (creditcard + repeat markers in Recent)
  → dashboard reload (totals, FIFO, Rhythm — all see the new entries)
later statement import → posting matches amount+merchant+window → merges into the entry (GOL-79)
```

## Edge cases

- Away 8 weeks, monthly sub → two entries (both real charges). Weekly sub → up to ~8; truth is the feature.
- Sub cancelled outside the app: fabricates until the user deletes one entry — deletion mutes the sub (see revision above); the mute lifts only when new real evidence arrives.
- Clock moved backwards → `dueCharges` yields `[]` (non-positive gaps).
- Statement posting >4 days after the due date (either side) → reconcile misses → leftover deletable duplicate, per the codebase principle (never hide a real expense).
- First run after upgrade: horizon caps the backfill at ~2 monthly cycles per sub — no months-deep history dump.
- CloudKit two-device race: both devices may settle the same due date before sync → two `.automatic` entries with distinct UUID keys. Rare (requires near-simultaneous foregrounds), visible, deletable; accepted for v1.

## Tests

- **`SubscriptionSettlementPlannerTests` (GoldengoCoreTests):** single missed monthly charge; multiple periods; horizon cutoff drops old misses; nothing due → empty; backwards clock → empty; calendar-accurate month ends (Jan 31 → Feb 28).
- **`SettleDueSubscriptionsTests` (GoldengoDataTests):** creates `.automatic` entries dated at due dates with the sub's amount/currency and last-charge merchant string, linked to the sub; second sweep is a no-op; skips unconfirmed / dismissed / variable-amount / archived; merchant category default applied.
- **`ReconcileImportTests` (extend):** an imported row 2 days after a settled entry's date merges into it (no duplicate).
- `RootView` wiring: device-verified.

## Out of scope (explicit, v1)

- Any Re-entry screen change (this spec *closes* the GOL-84 fast-follow as "won't do on Re-entry").
- Variable-amount estimation (utility-style subs stay manual/import-only).
- Notifications or banners announcing auto-logged entries (Recent's markers are the surface).
- Per-subscription or global auto-settle toggles.
- Cross-device settlement coordination (accepted rare-duplicate race above).
