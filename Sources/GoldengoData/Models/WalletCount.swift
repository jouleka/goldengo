import Foundation
import SwiftData
import GoldengoCore

/// One denomination count of the physical wallet (GOL-95). Append-only: a wrong count is
/// fixed by counting again. CloudKit-friendly defaults; tally stored as a Codable JSON blob.
@Model
public final class WalletCount {
    public var date: Date = Date.now
    public var tallyData: Data = Data()
    public var total: Decimal = 0          // denormalized; NEVER compared inside a #Predicate
    public var isArchived: Bool = false

    public init(tally: DenominationTally, date: Date = .now) {
        self.date = date
        self.tallyData = (try? JSONEncoder().encode(tally)) ?? Data()
        self.total = tally.total
    }
}
