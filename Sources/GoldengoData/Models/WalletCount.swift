import Foundation
import SwiftData
import GoldengoCore

/// One wallet baseline (GOL-95 v2): the user set what's actually in the wallet for one
/// currency — typed directly (no tally) or via a denomination count (tally kept). Append-only:
/// a wrong set is fixed by setting again. CloudKit-friendly defaults; tally is a Codable blob.
@Model
public final class WalletCount {
    public var date: Date = Date.now
    public var tallyData: Data = Data()    // empty when the balance was typed, not counted
    public var total: Decimal = 0          // denormalized; NEVER compared inside a #Predicate
    public var currencyCode: String = "ALL"
    public var isArchived: Bool = false

    public init(total: Decimal, tally: DenominationTally?, currencyCode: String, date: Date = .now) {
        self.date = date
        self.total = total
        self.currencyCode = currencyCode
        self.tallyData = tally.flatMap { try? JSONEncoder().encode($0) } ?? Data()
    }
}
