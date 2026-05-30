import Foundation

/// The common, `Sendable` shape every connector emits. The ingestion pipeline
/// (later plan) maps these into persisted `Expense` records, using `dedupeKey`
/// to merge rather than double-count (spec §6, §7).
public struct NormalizedTransaction: Hashable, Sendable {
    public var externalID: String?
    public var amount: Decimal
    public var currency: CurrencyCode
    public var date: Date
    public var rawMerchant: String?
    public var kind: TransactionKind
    public var accountRef: String?

    public init(externalID: String?, amount: Decimal, currency: CurrencyCode,
                date: Date, rawMerchant: String?, kind: TransactionKind,
                accountRef: String?) {
        self.externalID = externalID
        self.amount = amount
        self.currency = currency
        self.date = date
        self.rawMerchant = rawMerchant
        self.kind = kind
        self.accountRef = accountRef
    }

    /// Stable key for reconciliation. Prefers a provider id; otherwise a
    /// day-granularity composite so a manual entry and its later-imported
    /// statement row collapse to one record.
    public var dedupeKey: String {
        if let id = externalID, !id.isEmpty { return "ext:\(id)" }
        let day = Self.dayFormatter.string(from: date)
        let amt = NSDecimalNumber(decimal: amount).stringValue
        return "cmp:\(day)|\(amt)|\(rawMerchant ?? "")|\(accountRef ?? "")"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
