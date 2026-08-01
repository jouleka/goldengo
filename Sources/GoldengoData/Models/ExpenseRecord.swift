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
    /// Independent from category: "Business", "Travel", a project name, etc.
    public var contextName: String?
    /// A dismissed/confirmed Review Inbox issue should not return on every load.
    public var reviewedAt: Date?
    /// Optional investment destination for wealth-building expense rows.
    public var investmentAccountID: String?
    /// Dedupe key of the purchase this refund reverses. A stable string keeps the link
    /// CloudKit-friendly even when the original transaction is later archived.
    public var refundedExpenseKey: String?
    @Relationship(deleteRule: .cascade, inverse: \ExpenseSplitRecord.expense)
    public var splits: [ExpenseSplitRecord]? = []

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

    /// Consumption spend only. Investment contributions remain expense-kind so they still drain
    /// the wallet/provenance ledger, but headings that say "spent" must not treat them as consumed.
    var countsAsSpending: Bool {
        kindRaw == TransactionKind.expense.rawValue && consumptionAmount > 0
    }

    /// Whether this row participates in net-spend totals. Refunds participate with a negative
    /// effect but deliberately remain excluded from subscription/rhythm detection.
    var affectsSpendingTotals: Bool {
        (kindRaw == TransactionKind.expense.rawValue || kindRaw == TransactionKind.refund.rawValue)
            && consumptionAmount > 0
    }

    /// Signed reporting effect: purchases add spend, refunds remove it.
    var spendingEffect: Decimal {
        guard affectsSpendingTotals else { return 0 }
        return kindRaw == TransactionKind.refund.rawValue ? -consumptionAmount : consumptionAmount
    }

    /// The consumption portion of this outflow. A mixed purchase can contain both consumption and
    /// investment allocations; wallet/provenance still drains by the full parent amount.
    var consumptionAmount: Decimal {
        guard kindRaw == TransactionKind.expense.rawValue || kindRaw == TransactionKind.refund.rawValue
        else { return 0 }
        let parts = splits ?? []
        guard !parts.isEmpty else {
            return SpendingCategoryCatalog.classify(category?.name).purpose == .wealth ? 0 : amount
        }
        return parts.reduce(Decimal.zero) { total, part in
            SpendingCategoryCatalog.classify(part.categoryName).purpose == .wealth ? total : total + part.amount
        }
    }
}
