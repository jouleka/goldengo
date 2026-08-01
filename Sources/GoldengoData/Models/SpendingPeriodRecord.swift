import Foundation
import SwiftData
import GoldengoCore

/// The user's explicit answer to “how much money is this plan for, and until when?”. There is one
/// active record; keeping it in SwiftData makes the contract portable across devices with the rest
/// of the financial model instead of hiding it in UserDefaults.
@Model
public final class SpendingPeriodRecord {
    public var id: String = "active-spending-period"
    public var startDate: Date = Date.now
    public var endDate: Date = Date.now
    public var fundingModeRaw: String = SpendingPeriodFundingMode.liveBalances.rawValue
    public var startingAmount: Decimal?
    public var currencyCode: String = "ALL"
    public var cadenceRaw: String = SpendingPeriodCadence.once.rawValue
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var isArchived: Bool = false

    public init(startDate: Date = .now, endDate: Date = .now,
                fundingMode: SpendingPeriodFundingMode = .liveBalances,
                startingAmount: Decimal? = nil, currencyCode: String = "ALL",
                cadence: SpendingPeriodCadence = .once) {
        self.startDate = startDate; self.endDate = endDate
        self.fundingModeRaw = fundingMode.rawValue; self.startingAmount = startingAmount
        self.currencyCode = currencyCode; self.cadenceRaw = cadence.rawValue
    }

    public var fundingMode: SpendingPeriodFundingMode {
        SpendingPeriodFundingMode(rawValue: fundingModeRaw) ?? .liveBalances
    }
    public var cadence: SpendingPeriodCadence {
        SpendingPeriodCadence(rawValue: cadenceRaw) ?? .once
    }
}
