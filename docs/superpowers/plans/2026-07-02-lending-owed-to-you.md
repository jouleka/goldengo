# Lending ("Owed to you") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lend money to a person (drains wallet/source, never counts as spending), track the claim as an "Owed to you" card, log paybacks, forgive, and nudge after 30 days.

**Architecture:** Two new `TransactionKind`s (`lent`, `repayment`) opted into the wallet ledger and FIFO allocator explicitly; a `LoanRecord` per person with derived balances; store APIs in `IngestionStore+Loans`; reminders via a pure `LoanReminderPlanner` through the existing scheduler (distinct id prefix); Wallet-tab UI (Lend pill, cards, adjust sheet) in the established idioms. Spec: `docs/superpowers/specs/2026-07-02-lending-owed-to-you-design.md`.

**Tech Stack:** Swift / SwiftData / SwiftUI, XCTest via `swift test`.

## Global Constraints

- New `@Model` properties/models: literal defaults + declared inverse (CloudKit).
- Never compare `Decimal` in `#Predicate`; filter in memory.
- No async tests in GoldengoIntentsTests (AppIntents zombie); nothing here touches it.
- `.lent`/`.repayment` must NEVER appear in spend totals or the subscription detector (all filter `kindRaw == expense` — verify with tests, don't assume).
- Full `swift test` green before each commit; suite run 3× at the end (layout-sensitive latent crash history).

---

### Task 1: Core — `TransactionKind` cases + `LoanReminderPlanner`

**Files:**
- Modify: `Sources/GoldengoCore/TransactionKind.swift`
- Create: `Sources/GoldengoCore/LoanReminderPlanner.swift`
- Test: `Tests/GoldengoCoreTests/LoanReminderPlannerTests.swift`

**Interfaces (produces):**
```swift
public enum TransactionKind { case expense, income, transfer, lent, repayment }

public enum LoanReminderPlanner {
    public struct LoanInput: Sendable, Equatable {
        public var id: String            // LoanRecord id
        public var personName: String
        public var remainingText: String // preformatted Money string
        public var lastEventDate: Date   // newest lent/repayment event
        public init(id:personName:remainingText:lastEventDate:)
    }
    public struct Request: Sendable, Equatable {  // same shape the scheduler consumes
        public var id: String; public var title: String; public var body: String; public var fireDate: Date
    }
    public static let nudgeAfterDays = 30
    /// One nudge per loan with balance > 0 whose newest event is ≥ 30 days old (fire now → the
    /// scheduler's next-morning slot) or will become so (fire at lastEvent+30d). Disabled → [].
    public static func plan(_ loans: [LoanInput], enabled: Bool, now: Date, calendar: Calendar) -> [Request]
}
```

- [ ] Failing tests: enabled loan idle 31 days → one request ("Andi has owed you ALL 5,000 for a month.", fireDate = lastEvent+30d); idle 5 days → request with FUTURE fireDate = lastEvent+30d (pre-scheduled, re-armed on events because the caller replans after every mutation); disabled → []; balance handled by caller (planner receives only open loans).
- [ ] Implement (pure; body text uses remainingText + personName; fireDate = calendar.date(byAdding: .day, value: 30, to: lastEventDate)).
- [ ] Adding enum cases: `swift build` — fix every exhaustive-switch compile error by choosing the exclusion/inclusion each site needs (each is a deliberate opt-in per the spec; document with a comment).
- [ ] Full `swift test` → green. Commit `feat(core): lent/repayment kinds + LoanReminderPlanner`.

### Task 2: Data — `LoanRecord`, relationship, schema, `IngestionStore+Loans`

**Files:**
- Create: `Sources/GoldengoData/Models/LoanRecord.swift` (mirror SourceRecord: id/personName/currencyCode/colorIndex/createdAt/isArchived + `@Relationship(deleteRule: .nullify, inverse: \ExpenseRecord.loan) events: [ExpenseRecord]?`)
- Modify: `Sources/GoldengoData/Models/ExpenseRecord.swift` (add `public var loan: LoanRecord?`)
- Modify: `Sources/GoldengoData/ModelContainer+Goldengo.swift` (register `LoanRecord.self`)
- Create: `Sources/GoldengoData/IngestionStore+Loans.swift`
- Test: `Tests/GoldengoDataTests/LoanStoreTests.swift`

**Interfaces (produces):**
```swift
public struct LoanBalance: Sendable, Identifiable, Equatable {
    public let id, personName, currencyCode: String
    public let colorIndex: Int
    public let lentTotal, remaining: Decimal
    public let sinceDate: Date        // oldest lent event
    public let lastEventDate: Date    // newest event (reminder re-arm anchor)
}
extension IngestionStore {
    public func lend(amount: Decimal, currency: CurrencyCode, personName: String,
                     fundedBySourceID: String? = nil, date: Date = .now) throws
    public func logRepayment(amount: Decimal, loanID: String, date: Date = .now) throws  // strict: 0 < amount <= remaining
    public func renameLoan(id: String, to newName: String) throws                        // refuse live duplicate (like renameSource)
    public func forgiveLoan(id: String, date: Date = .now) throws                        // remaining → visible "Gifts" expense (wallet-neutral), archive loan
    public func deleteLoan(id: String) throws                                            // archive loan + events (mirror deleteSource)
    public func loanBalances() throws -> [LoanBalance]
}
```
Key mechanics:
- `lend`: find-or-create LoanRecord by case-insensitive personName among non-archived (palette slot like sources); insert ExpenseRecord kind `.lent`, source `.manual`, dedupeKey `"lent:\(UUID())"`, `fundedBySourceID` as passed (nil+manual = wallet-cash, same rule as expenses), `loan` linked, merchantName = personName.
- `logRepayment`: ExpenseRecord kind `.repayment`, dedupeKey `"repay:\(UUID())"`, `fundedBySourceID = FundingPin.wallet` (v1: cash comes home), loan linked, merchantName = personName. Guard `0 < amount <= remaining`.
- `forgiveLoan`: remaining via balances; `logEntry(amount: remaining, …, categoryName: "Gifts", merchant: personName, source: .manual, keyPrefix: Self.forgiveKeyPrefix, date: date)`; archive the LoanRecord only (events stay — the money really left when it was lent). `forgiveKeyPrefix = "forgive"`; the expense is REAL spending (totals) but wallet-neutral (Task 3 exclusion) because the wallet already drained at lend time.
- Both lend + repayment call `refreshSharedPocket()` + widget reload (they move the pocket claim) and `try seedWalletBaselineIfMissing` is NOT needed (lend only drains; repayment inflow without a baseline should seed like cash income does — reuse the same call with the repayment date).

- [ ] Failing tests: find-or-create converges case-insensitively; balances derive (lend 5000, repay 2000 → remaining 3000, lentTotal 5000); strict repay guard (0, negative, > remaining → no-op, balance unchanged); rename keeps balance & refuses duplicates; delete archives loan and its events (loanBalances empty; re-lend same name starts fresh); forgive: balance→archived, one visible "Gifts" expense of the remaining amount exists (`recentExpenses` contains kind .expense, categoryName "Gifts", dedupeKey prefix "forgive:").
- [ ] Implement; full suite; commit `feat(data): LoanRecord + lend/repay/forgive/delete/balances`.

### Task 3: Data — ledger opt-ins (wallet + allocator) 

**Files:**
- Modify: `Sources/GoldengoData/IngestionStore+Wallet.swift` (`cashFlows`)
- Modify: `Sources/GoldengoData/IngestionStore+Provenance.swift` (`buildAllocatorInputs`)
- Test: append `Tests/GoldengoDataTests/WalletTests.swift` + `Tests/GoldengoDataTests/LoanStoreTests.swift`

`cashFlows` additions (inside the existing switch):
```swift
case TransactionKind.lent.rawValue where r.fundedBySourceID == FundingPin.wallet
        || (r.fundedBySourceID == nil && r.sourceRaw == manualRaw):
    // Lending is cash leaving the pocket — drains exactly like a cash spend.
    return CashLedger.Flow(amount: abs(r.amount), isInflow: false)
case TransactionKind.repayment.rawValue where r.fundedBySourceID == FundingPin.wallet:
    // Payback is cash coming home.
    return CashLedger.Flow(amount: abs(r.amount), isInflow: true)
```
plus the expense case's drift exclusion extends to the forgive prefix:
```swift
case TransactionKind.expense.rawValue where !r.dedupeKey.hasPrefix(driftPrefix)
        && !r.dedupeKey.hasPrefix(Self.forgiveKeyPrefix + ":") && …existing…
    // forgive: the wallet already drained at LEND time — the forgiveness expense is a
    // reclassification of that money, never a second drain.
```
`buildAllocatorInputs` addition: source-pinned `.lent` drains its pool:
```swift
} else if r.kindRaw == lentRaw, let pinned = r.fundedBySourceID, pinned != FundingPin.wallet {
    outflows.append(.init(id: r.dedupeKey, amount: abs(r.amount),
                          currency: CurrencyCode(r.currencyCode), date: r.date,
                          pinnedSourceID: pinned))
}
```
(repayments are wallet-only in v1 — never pool inflows; forgive expenses are nil-pin manual = already skipped as cash-funded.)

- [ ] Failing tests (intent):
  - wallet: lend 1000 cash from a 5000 wallet → expected 4000; repay 400 → 4400; forgive the rest → expected STAYS 4400 (no second drain) while todayTotal gains the forgiven 600.
  - provenance: lend pinned to a source pool → pool remaining drops; wallet untouched.
  - totals: `todayTotal` after a lend + a repayment = 0 (lending is not spending).
- [ ] Implement; full suite; commit `feat(data): lending flows through wallet ledger + allocator`.

### Task 4: Reminders + Settings toggle

**Files:**
- Modify: `Sources/GoldengoData/SharedSummary.swift` (`loanRemindersKey = "loanRemindersEnabled"`, reader `loanRemindersEnabled()` defaulting **true** when unset)
- Modify: `Sources/GoldengoFeatures/Subscriptions/SubscriptionReminders.swift` (`LocalNotificationScheduler.sync` gains `prefix: String = "sub-reminder:"`; internals use it)
- Modify: `Sources/GoldengoFeatures/Provenance/SourcesModel.swift` (after `load()` and every loan mutation: build `LoanReminderPlanner.plan` inputs from open loans and `LocalNotificationScheduler.sync(_, prefix: "loan-reminder:")`)
- Modify: `Sources/GoldengoFeatures/Settings/SettingsView.swift` (toggle "Remind me about money owed" in the reminders section, bound to the shared-defaults key)
- Test: `Tests/GoldengoDataTests/SharedSummaryTests.swift` (default-true semantics)

- [ ] Failing test: `loanRemindersEnabled()` true when unset, false after set false, true after set true (WHY: opt-out — a lent debt silently forgotten is the failure mode this feature exists to prevent).
- [ ] Implement; full suite; commit `feat(loans): 30-day owed-to-you nudges + settings toggle`.

### Task 5: UI — Lend pill, Owed-to-you cards, sheets, Recent rows

**Files:**
- Modify: `Sources/GoldengoFeatures/Provenance/SourcesModel.swift` (published `loans: [LoanBalance]` loaded in `load()`; wrappers `lend`, `repay`, `renameLoan`, `forgiveLoan`, `deleteLoan` — each calls store + `load()`)
- Create: `Sources/GoldengoFeatures/Provenance/LendView.swift` (AddIncome idiom: serif title field for the person with chips of existing debtor names + ＋New pattern collapsed to: person name field prefilled empty + chips row; amount + currency menu; "From" picker Wallet — cash / sources (QuickAdd's paidFrom idiom); When row; GoldButton "Lend it"; `.ignoresSafeArea(.keyboard, edges: .bottom)`)
- Create: `Sources/GoldengoFeatures/Provenance/AdjustLoanView.swift` (AdjustSourceView idiom: serif rename field; caption "Andi owes you ALL 5,000 since Jun 12."; amount field prefilled with remaining labelled "They paid back…"; GoldButton "Log payback"; destructive rows: "Forgive the rest" (alert: logs a Gifts expense) + "Delete" (alert: history archives))
- Modify: `Sources/GoldengoFeatures/Provenance/SourcesView.swift` (header gains "Lend" pill beside Income; "OWED TO YOU" section of cards between wallet card and Sources — name+dot, amount, "since …", tap → AdjustLoanView sheet, swipe leading Edit / trailing Delete-with-confirm; sheets wired)
- Modify: `Sources/GoldengoFeatures/Shared/ExpenseRowView.swift` (`.lent`: neutral amount, subtext "lent · owed to you"; `.repayment`: "+" income-green amount, subtext "paid back")

- [ ] Implement following the named idioms exactly (all four sheets in this codebase share the field/chip/GoldButton patterns).
- [ ] `swift build` + full `swift test`; commit `feat(loans): Owed-to-you UI — Lend pill, cards, payback/forgive sheet`.

### Task 6: Verification

- [ ] Full `swift test` ×3 consecutive (latent-layout history) — all green, no signals.
- [ ] `xcodebuild … build` + `devicectl … install`; push main.
- [ ] User walk: Lend 1000 to "Andi" → wallet expected drops; card appears; Recent shows "Andi · lent"; payback 400 → card shrinks, wallet rises; forgive → Gifts expense in Recent, card gone.
