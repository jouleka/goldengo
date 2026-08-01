import Foundation
import SwiftData

@Model
public final class InvestmentAccountRecord {
    public var id: String = ""
    public var name: String = ""
    public var kindName: String = "Investment"
    public var currencyCode: String = "ALL"
    public var currentValue: Decimal = 0
    public var valueAsOf: Date = Date.now
    public var colorIndex: Int = 0
    public var createdAt: Date = Date.now
    public var isArchived: Bool = false

    public init(id: String = UUID().uuidString, name: String = "", kindName: String = "Investment",
                currencyCode: String = "ALL", currentValue: Decimal = 0,
                valueAsOf: Date = .now, colorIndex: Int = 0) {
        self.id = id; self.name = name; self.kindName = kindName; self.currencyCode = currencyCode
        self.currentValue = currentValue; self.valueAsOf = valueAsOf; self.colorIndex = colorIndex
    }
}

@Model
public final class InvestmentEntryRecord {
    public var id: String = ""
    public var accountID: String = ""
    public var amount: Decimal = 0
    public var currencyCode: String = "ALL"
    public var date: Date = Date.now
    public var kindRaw: String = "contribution"
    public var transactionKey: String?
    public var note: String?

    public init(id: String = UUID().uuidString, accountID: String = "", amount: Decimal = 0,
                currencyCode: String = "ALL", date: Date = .now,
                kind: String = "contribution", transactionKey: String? = nil, note: String? = nil) {
        self.id = id; self.accountID = accountID; self.amount = amount
        self.currencyCode = currencyCode; self.date = date; self.kindRaw = kind
        self.transactionKey = transactionKey; self.note = note
    }
}
