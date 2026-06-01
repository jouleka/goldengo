import Foundation
import SwiftData

@Model
public final class AccountRecord {
    public var name: String = "Cash"
    public var typeRaw: String = "cash"        // bankCard | cash | cryptoWallet | cryptoExchange
    public var currencyCode: String = "ALL"
    public var connectorID: String?
    // Inverse of ExpenseRecord.account. REQUIRED for CloudKit: SwiftData+CloudKit rejects a schema
    // where any relationship lacks an inverse, which otherwise crashes the app on launch.
    @Relationship(deleteRule: .nullify, inverse: \ExpenseRecord.account)
    public var expenses: [ExpenseRecord]? = []

    public init(name: String = "Cash", typeRaw: String = "cash",
                currencyCode: String = "ALL", connectorID: String? = nil) {
        self.name = name; self.typeRaw = typeRaw
        self.currencyCode = currencyCode; self.connectorID = connectorID
    }
}
