import Foundation

/// Billing cadence with explicit day-tolerance bands to avoid monthly-vs-4-weekly aliasing (spec §9).
public enum SubscriptionCadence: String, Sendable, CaseIterable, Codable {
    case weekly, monthly, quarterly, yearly

    /// Inclusive day-gap band a consecutive interval must fall in to count as this cadence.
    public var dayBand: ClosedRange<Int> {
        switch self {
        case .weekly:    return 5...9      // 7 ± 2
        case .monthly:   return 28...31
        case .quarterly: return 88...93
        case .yearly:    return 360...370
        }
    }

    /// Minimum occurrences required to surface a candidate at this cadence.
    /// Long cadences relax the bar — 3 yearly charges would take ~3 years (spec §9).
    public var minimumOccurrences: Int { self == .yearly ? 2 : 3 }

    /// Advance a date by exactly one period of this cadence (calendar-accurate, not 30-day approx).
    public func advance(_ date: Date, by periods: Int = 1, calendar: Calendar) -> Date {
        var comps = DateComponents()
        switch self {
        case .weekly:    comps.day = 7 * periods
        case .monthly:   comps.month = periods
        case .quarterly: comps.month = 3 * periods
        case .yearly:    comps.year = periods
        }
        return calendar.date(byAdding: comps, to: date) ?? date
    }
}

/// A normalized, `Sendable` occurrence the detector reasons over. The persistence layer maps
/// its records into these; the detector stays pure and dependency-free.
public struct TransactionOccurrence: Hashable, Sendable {
    public var id: String          // stable record key (e.g. dedupeKey) for traceability
    public var date: Date
    public var amount: Decimal     // positive magnitude
    public var currency: CurrencyCode
    public var merchant: String?   // raw; detector normalizes via MerchantNormalizer

    public init(id: String, date: Date, amount: Decimal, currency: CurrencyCode, merchant: String?) {
        self.id = id; self.date = date; self.amount = amount
        self.currency = currency; self.merchant = merchant
    }
}

/// A detected recurring-charge candidate. Never asserted — surfaced for user confirmation (spec §9).
public struct SubscriptionCandidate: Hashable, Sendable, Identifiable {
    public var id: String              // matchKey: "<normalizedMerchant>|<cadence>|<currency>"
    public var displayName: String     // most recent non-empty raw merchant
    public var normalizedMerchant: String
    public var amount: Decimal         // representative (median) positive magnitude
    public var currency: CurrencyCode
    public var cadence: SubscriptionCadence
    public var occurrenceCount: Int
    public var firstCharge: Date
    public var lastCharge: Date
    public var predictedNextCharge: Date
    public var isVariableAmount: Bool  // utilities etc.
    public var hadTrial: Bool          // first charge 0 / off-amount
    public var confidence: Double      // 0...1, interval regularity × occurrence weight
    public var memberIDs: [String]     // occurrence ids that formed this series

    public init(id: String, displayName: String, normalizedMerchant: String, amount: Decimal,
                currency: CurrencyCode, cadence: SubscriptionCadence, occurrenceCount: Int,
                firstCharge: Date, lastCharge: Date, predictedNextCharge: Date,
                isVariableAmount: Bool, hadTrial: Bool, confidence: Double, memberIDs: [String]) {
        self.id = id; self.displayName = displayName; self.normalizedMerchant = normalizedMerchant
        self.amount = amount; self.currency = currency; self.cadence = cadence
        self.occurrenceCount = occurrenceCount; self.firstCharge = firstCharge
        self.lastCharge = lastCharge; self.predictedNextCharge = predictedNextCharge
        self.isVariableAmount = isVariableAmount; self.hadTrial = hadTrial
        self.confidence = confidence; self.memberIDs = memberIDs
    }
}
