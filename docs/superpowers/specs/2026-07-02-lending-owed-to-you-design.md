# Lending — "Owed to you" (design)

**Date:** 2026-07-02
**Status:** Direction approved 2026-07-02 (sub-project 2 of 3); spec pending user review

## Problem

Handing a friend 100 isn't an expense — the money left the pocket but became a claim.
Today the user must either log it as a fake expense (wrong: inflates spending, forgets the
debt) or not log it (wrong: wallet expected balance drifts and reconcile logs junk
"Unaccounted"). There is no concept of money that left but is still yours.

## Concept

**Lending = money that moved from your pocket/source into a per-person claim.** It drains
the wallet or source for real (the cash left), never counts as spending, and sits on the
Wallet tab as an "Owed to you" card until it comes home (repayment), or is forgiven (the
moment it truly becomes an expense). Goldengo nudges when a debt sits too long.

## Data model (GoldengoData)

1. **`LoanRecord`** (@Model, mirrors `SourceRecord`): `id` (UUID string), `personName`,
   `currencyCode`, `colorIndex`, `createdAt`, `isArchived`. Relationship `events:
   [ExpenseRecord]?` (inverse of new `ExpenseRecord.loan`). Balance is always **derived**
   (sum of lent − sum of repaid over non-archived events) — never stored, matching the
   allocator philosophy.
2. **`TransactionKind` gains `.lent` and `.repayment`.** Both are additive raw strings;
   every existing `kindRaw` switch ignores unknown kinds by default, so each consumer is
   opted in explicitly:
   - **Wallet ledger (`cashFlows`)**: `.lent` = outflow when wallet-funded (pinned wallet,
     or unpinned manual — same rule as expenses); `.repayment` = inflow when wallet-pinned.
   - **Provenance allocator (`buildAllocatorInputs`)**: source-pinned `.lent` = outflow
     draining that pool; `.repayment` into a source = inflow to that source's pool.
   - **Spend totals (today/dashboard/history/subscriptions detector)**: both kinds are
     **excluded** — lending is not spending; repayment is not income earned.
   - **Recent/History rows**: both kinds **shown** (they're real money movements) with
     their own row treatment ("→ Andi" / "Andi paid back"), excluded from day totals.
3. **Store APIs** (IngestionStore+Loans.swift):
   - `lend(amount:currency:personName:fundedBySourceID:date:)` — find-or-create the
     person's LoanRecord (case-insensitive name, like sources), insert a `.lent` event.
     Wallet-funded by default; source pin drains that source.
   - `logRepayment(amount:loanID:date:)` — insert `.repayment` linked to the loan,
     credited to the wallet ledger (cash back in hand). v1 is wallet-only; bank-side
     repayments arrive via statement import as income later. YAGNI.
   - `forgiveLoan(loanID:date:)` — logs the remaining balance as a real `.expense`
     (category "Gifts", visible, deletable) and archives the loan. Honest: forgiveness is
     the moment the money was spent.
   - `deleteLoan(loanID:)` — archives the loan AND its events (mirrors `deleteSource`:
     the claim and its history leave together; real wallet history is unaffected because
     archived events drop out of `cashFlows`).
   - `loanBalances() -> [LoanBalance]` — Sendable snapshots (id, personName, currency,
     colorIndex, lentTotal, remaining, lastEventDate, oldestUnpaidDate).
4. **Reminders**: `LoanReminderPlanner` (pure, GoldengoCore) — one nudge per loan when the
   newest `.lent` event is ≥ 30 days old and balance > 0, re-armed by any new event.
   Scheduled through the existing `LocalNotificationScheduler`, gated by a new Settings
   toggle "Remind me about money owed" (default ON). Copy: "Andi has owed you ALL 5,000
   for a month."

## UI (GoldengoFeatures)

5. **Wallet tab — "Owed to you" section** between the wallet card and Sources: one card
   per person (dot color, name, amount owed, "since Jun 12"). The section appears only
   when loans exist. Lending starts from the Income pill's sibling: a **"Lend" pill**
   next to "+ Income" in the Wallet header.
6. **LendView sheet** (idiom: AddIncome): person name field with chips of existing
   debtors + ＋New (same pattern as sources/categories), amount + currency menu, funded
   from (Wallet — cash default, or a source; same picker as QuickAdd's Paid from), When
   row. Gold button "Lend it".
7. **Loan card tap → AdjustLoanView sheet** (idiom: AdjustSourceView): serif name
   (rename), big amount field prefilled with what's owed for logging a repayment ("They
   paid back…" — saving the full amount closes the debt), plus **Forgive** (confirm:
   "Log the rest as a gift and stop tracking?") and **Delete** (confirm: history archives).
   Swipe on the card: leading Edit, trailing Delete (same as sources).
8. **Recent rows**: `.lent` shows "→ personName" with the loan's dot color; `.repayment`
   shows "personName paid back". Both render via ExpenseRowView with a kind tag and are
   excluded from the day-group totals (HomeData parity test updated).

## Testing (intent)

- Lending drains the wallet ledger exactly like a cash spend, and a pinned lend drains
  its source pool (WHY: the cash really left — otherwise reconcile logs junk Unaccounted).
- Lending never appears in today/dashboard/history spend totals (WHY: it's not spending;
  the whole point of the feature).
- Repayment credits the wallet and reduces the person's balance to zero on full payback;
  over-payback clamps at zero with the surplus logged as wallet-pinned income? **No —
  v1 rejects amounts above the balance** (strict; a tip from a friend is income, log it
  as income). UI caps the field.
- Forgive logs one visible expense for the remaining balance and archives the loan (WHY:
  no silent write-offs — spend totals become truthful at the moment of the decision).
- Reminder planner: nudges at ≥30 days unpaid, re-arms on new events, respects the toggle.
- Detector/subscription pipelines ignore `.lent`/`.repayment` (WHY: a monthly loan to your
  brother must never become a "subscription").

## Out of scope (v1)

- Money you OWE others (direction is one-way: owed to you).
- Bank-side repayments matching statement imports automatically.
- Interest, partial-forgive, due dates. Investing pots (sub-project 3).
