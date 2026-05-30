import Foundation
import SwiftData

@Model
public final class AccountRecord {
    public var name: String = "Cash"
    public var typeRaw: String = "cash"        // bankCard | cash | cryptoWallet | cryptoExchange
    public var currencyCode: String = "ALL"
    public var connectorID: String?

    public init(name: String = "Cash", typeRaw: String = "cash",
                currencyCode: String = "ALL", connectorID: String? = nil) {
        self.name = name; self.typeRaw = typeRaw
        self.currencyCode = currencyCode; self.connectorID = connectorID
    }
}
