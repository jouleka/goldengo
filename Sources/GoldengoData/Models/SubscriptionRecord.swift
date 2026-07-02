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
    /// User-declared via "Add subscription" (not a detector guess). Manual subs survive the
    /// reconcile pass with zero charge history and anchor their ghost schedule on
    /// `manualAnchorDate` until real charges exist.
    public var isManual: Bool = false
    /// The schedule origin the user declared (their "next charge" at add time). Immutable —
    /// `nextChargeDate` rolls forward for display, but due-charge generation must keep the
    /// original phase and never invent dues from before this date.
    public var manualAnchorDate: Date = Date.now
    public var detectedAt: Date = Date.now
    public var updatedAt: Date = Date.now

    // Expense charges auto-matched to this subscription (same normalized merchant + currency).
    // Inverse of `ExpenseRecord.subscription`; declared here only (CloudKit: inverse on one side).
    @Relationship(deleteRule: .nullify, inverse: \ExpenseRecord.subscription)
    public var charges: [ExpenseRecord]? = []

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
