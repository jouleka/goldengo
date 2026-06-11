import Foundation
import GoldengoCore

public enum AmountStyle: Sendable, Equatable {
    case signed(index: Int)                       // one column; sign = direction
    case debitCredit(debit: Int, credit: Int)     // separate columns (e.g. Raiffeisen DEBI/KREDI)
}

public struct ColumnMapping: Sendable, Equatable {
    public var dateIndex: Int
    public var amount: AmountStyle
    public var merchantIndex: Int
    public var externalIDIndex: Int?
    public var dateFormats: [String]              // try each in order
    public var decimalSeparator: String
    public var groupingSeparator: String
    public var currency: CurrencyCode
    /// Descriptions matching these (word-boundary, diacritic-insensitive) retag a debit row
    /// as `.transfer` — an ATM withdrawal feeding the wallet, not spend (GOL-95). Defaulted
    /// so existing construction sites are untouched; `detectMapping` fills both from the profile.
    public var atmKeywords: [String] = []
    /// Fee/commission wording that vetoes the ATM match — a fee is spend, never a wallet inflow.
    public var atmExclusionKeywords: [String] = []

    public init(dateIndex: Int, amount: AmountStyle, merchantIndex: Int, externalIDIndex: Int?,
                dateFormats: [String], decimalSeparator: String, groupingSeparator: String, currency: CurrencyCode) {
        self.dateIndex = dateIndex; self.amount = amount; self.merchantIndex = merchantIndex
        self.externalIDIndex = externalIDIndex; self.dateFormats = dateFormats
        self.decimalSeparator = decimalSeparator; self.groupingSeparator = groupingSeparator; self.currency = currency
    }
}
