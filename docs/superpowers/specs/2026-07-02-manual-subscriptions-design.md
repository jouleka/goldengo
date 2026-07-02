# Manual subscriptions — design

**Date:** 2026-07-02
**Status:** Approved (Option A)

## Problem

The Subscriptions screen is detection-only: a subscription surfaces only after the same
normalized merchant is charged ≥3 times (≥2 for yearly) at a regular cadence in the user's
expense history. Users whose subscriptions bill outside their imported/logged data (iCloud,
Hetzner, Claude on a foreign card) see an empty screen and have no way to add one. There is
no "Add subscription" anywhere.

## Decision

Add first-class **manual subscriptions** that create the same `SubscriptionRecord` the
detector creates — pre-confirmed and flagged `isManual` — so everything downstream comes
free: the Tracked list, charge reminders, Home's Upcoming, and due-date **one-tap ghosts**
in Recent. Nothing is ever auto-logged (the app's no-silent-fabrication rule): a due charge
surfaces as a ghost; tapping it logs the real expense.

Rejected alternative: seeding each manual sub by logging its "last real charge" as a
backdated expense. That silently drains the wallet ledger and pollutes past totals.

## Data & store changes (GoldengoData)

1. **`SubscriptionRecord.isManual: Bool = false`** — additive property with a default
   (SwiftData lightweight migration; CloudKit-safe).

2. **`addManualSubscription(name:amount:currency:cadence:nextChargeDate:) `** (IngestionStore)
   - `matchKey = "<MerchantNormalizer.normalize(name)>|<cadence>|<currency>"` — identical
     key scheme to detection, so a manual add and a later detected series **converge on one
     record** instead of duplicating.
   - If an active record with that key exists: set `isConfirmed = true`, `isDismissed = false`,
     `isManual = true`, update amount/cadence/nextChargeDate/displayName.
   - Else insert a new record: confirmed, `isManual = true`, `occurrenceCount = 0`,
     `confidence = 1` (it is not a guess), `nextChargeDate` = the user's date.
   - Empty/whitespace name or amount ≤ 0 → no-op (UI also guards).

3. **`refreshSubscriptions` reconcile pass** — two manual-aware changes:
   - A confirmed **manual** record with zero charge history is **kept**, not archived
     (today: confirmed + `currentChargeCount == 0` → archived, which would delete a manual
     sub on the next refresh).
   - A manual record not updated by detection gets its `nextChargeDate` **rolled forward**
     past `now` via `cadence.advance` so "Next: …" never shows a stale past date.

4. **`pendingSubscriptionCharges`** — manual subs with **no billing evidence** anchor their
   due-charge schedule on `nextChargeDate` (`anchor = notBefore = nextChargeDate`) instead
   of the freshest evidence row. `dueCharges`'s existing `anchor <= now` guard means a
   future date produces no ghost until the day arrives. Once the user taps a ghost (or a
   statement import lands the charge), real evidence exists and the normal evidence-anchored
   path takes over. The coverage check (a nearby real row suppresses the due) applies
   unchanged; a merchant with no rows at all simply has nothing to suppress.

## UI changes (GoldengoFeatures)

5. **AddSubscriptionView** (new sheet, quiet-luxe idiom shared with AddIncome/QuickAdd):
   name field, amount + one-tap currency menu, cadence segmented control
   (Weekly / Monthly / Quarterly / Yearly, default Monthly), "Next charge" date picker
   (default today), gold **Track subscription** button. Presented from:
   - a toolbar **＋** on SubscriptionsView, and
   - the empty state's CTA.

6. **SubscriptionsView**: manual subs appear under **Tracked** (they're confirmed).
   Existing swipe "Not a subscription" already stops tracking them — no new affordance.
   Empty-state copy gains the manual path: "Add one yourself, or import statements and
   Goldengo lists repeats here."

7. **SubscriptionsModel**: `addManual(...)` wrapper → store call + `load()` (which also
   re-syncs reminders — manual subs get reminders for free because reminder sync reads the
   confirmed set).

## Testing (intent, not just behavior)

- `addManualSubscription` creates a confirmed record that `subscriptionCandidates()`
  surfaces under Tracked; adding the same name+cadence+currency twice converges on one
  record (WHY: the matchKey scheme is the dedupe contract with detection).
- `refreshSubscriptions` keeps a chargeless manual sub (WHY: reconcile-archive exists to
  drop stale *guesses*; a manual sub is a user statement, not a guess) and rolls its stale
  `nextChargeDate` forward.
- `pendingSubscriptionCharges` yields no ghost before the user's chosen date and exactly
  one once it passes (WHY: predictions surface as one-tap ghosts, never auto-logged).
- A detected series for the same merchant later updates the same record without losing
  `isConfirmed`/`isManual`.

## Out of scope

- Editing a tracked subscription's fields after creation (re-adding with the same name
  updates it — sufficient for v1).
- Price-change detection for manual subs, notifications copy changes, Plaid feeds.
