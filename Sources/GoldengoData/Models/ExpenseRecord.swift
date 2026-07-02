import Foundation
import SwiftData
import GoldengoCore

@Model
public final class ExpenseRecord {
    public var amount: Decimal = 0
    public var currencyCode: String = "ALL"
    public var date: Date = Date.now
    public var merchantName: String?
    public var note: String?
    public var kindRaw: String = TransactionKind.expense.rawValue
    public var sourceRaw: String = ExpenseSource.manual.rawValue
    public var dedupeKey: String = ""
    public var isArchived: Bool = false          // soft-delete tombstone (CloudKit-friendly)
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var category: CategoryRecord?
    public var account: AccountRecord?
    // Confirmed subscription this charge was auto-matched to (inverse declared on SubscriptionRecord).
    // Left defaulting to nil; set by the auto-match linker, not in init.
    public var subscription: SubscriptionRecord?
    // The named money source this INCOME record belongs to (nil for expenses + un-sourced income).
    // Set by logIncome, not in init. Inverse declared on SourceRecord.incomes.
    public var provenanceSource: SourceRecord?
    // The per-person loan this LENT/REPAYMENT event belongs to (nil for every other kind).
    // Set by lend/logRepayment, not in init. Inverse declared on LoanRecord.events.
    public var loan: LoanRecord?
    // GOL-89: the user-chosen funding source for this EXPENSE (the "pin"); nil = automatic FIFO.
    // A plain SourceRecord.id string — NOT the provenanceSource relationship, whose inverse feeds
    // source inflow totals (income-only). Additive optional → lightweight CloudKit-safe migration.
    public var fundedBySourceID: String?

    public init(amount: Decimal = 0, currencyCode: String = "ALL", date: Date = .now,
                merchantName: String? = nil, note: String? = nil,
                kind: TransactionKind = .expense, source: ExpenseSource = .manual,
                dedupeKey: String = "", category: CategoryRecord? = nil,
                account: AccountRecord? = nil) {
        self.amount = amount; self.currencyCode = currencyCode; self.date = date
        self.merchantName = merchantName; self.note = note
        self.kindRaw = kind.rawValue; self.sourceRaw = source.rawValue
        self.dedupeKey = dedupeKey; self.category = category; self.account = account
    }

    public var kind: TransactionKind { TransactionKind(rawValue: kindRaw) ?? .expense }
    public var source: ExpenseSource { ExpenseSource(rawValue: sourceRaw) ?? .manual }
    public var money: Money { Money(amount: amount, currency: CurrencyCode(currencyCode)) }
}
