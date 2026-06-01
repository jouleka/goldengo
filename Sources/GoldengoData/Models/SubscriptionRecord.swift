import Foundation
import SwiftData
import GoldengoCore

@Model
public final class SubscriptionRecord {
    public var matchKey: String = ""               // "<normalizedMerchant>|<cadence>|<currency>"
    public var displayName: String = ""
    public var normalizedMerchant: String = ""
    public var amount: Decimal = 0
    public var currencyCode: String = "ALL"
    public var cadenceRaw: String = SubscriptionCadence.monthly.rawValue
    public var nextChargeDate: Date = Date.now
    public var occurrenceCount: Int = 0
    public var confidence: Double = 0
    public var isVariableAmount: Bool = false
    public var hadTrial: Bool = false
    public var isConfirmed: Bool = false           // user said "yes, it's a subscription"
    public var isDismissed: Bool = false           // user said "not a subscription"
    public var isArchived: Bool = false            // tombstone (CloudKit-friendly)
    public var detectedAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public init(matchKey: String = "", displayName: String = "", normalizedMerchant: String = "",
                amount: Decimal = 0, currencyCode: String = "ALL",
                cadence: SubscriptionCadence = .monthly, nextChargeDate: Date = .now,
                occurrenceCount: Int = 0, confidence: Double = 0,
                isVariableAmount: Bool = false, hadTrial: Bool = false) {
        self.matchKey = matchKey; self.displayName = displayName
        self.normalizedMerchant = normalizedMerchant; self.amount = amount
        self.currencyCode = currencyCode; self.cadenceRaw = cadence.rawValue
        self.nextChargeDate = nextChargeDate; self.occurrenceCount = occurrenceCount
        self.confidence = confidence; self.isVariableAmount = isVariableAmount; self.hadTrial = hadTrial
    }

    public var cadence: SubscriptionCadence { SubscriptionCadence(rawValue: cadenceRaw) ?? .monthly }
}
