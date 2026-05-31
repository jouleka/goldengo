import Foundation
import GoldengoCore

public struct ColumnMapping: Sendable, Equatable {
    public var dateIndex: Int
    public var amountIndex: Int
    public var merchantIndex: Int
    public var externalIDIndex: Int?
    public var dateFormat: String
    public var decimalSeparator: String
    public var groupingSeparator: String
    public var currency: CurrencyCode

    public init(dateIndex: Int, amountIndex: Int, merchantIndex: Int, externalIDIndex: Int?,
                dateFormat: String, decimalSeparator: String, groupingSeparator: String,
                currency: CurrencyCode) {
        self.dateIndex = dateIndex; self.amountIndex = amountIndex
        self.merchantIndex = merchantIndex; self.externalIDIndex = externalIDIndex
        self.dateFormat = dateFormat; self.decimalSeparator = decimalSeparator
        self.groupingSeparator = groupingSeparator; self.currency = currency
    }
}
