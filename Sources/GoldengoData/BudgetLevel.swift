import Foundation

/// How a category's month spend sits against its cap. All-Decimal comparison (in memory,
/// never inside a #Predicate) so the 85%/100% boundaries are exact — no float drift.
public enum BudgetLevel: String, Sendable, Equatable {
    case noBudget, ok, near, over

    /// The "close to your cap" line, as a fraction of the cap. Fixed in v1.
    public static let nearNumerator = Decimal(85)
    public static let nearDenominator = Decimal(100)

    public static func forSpend(_ spent: Decimal, cap: Decimal?) -> BudgetLevel {
        guard let cap, cap > 0 else { return .noBudget }
        if spent >= cap { return .over }
        if spent >= cap * nearNumerator / nearDenominator { return .near }
        return .ok
    }

    /// Escalation order for notify-once dedupe. noBudget/ok share 0 (no alert).
    public var rank: Int {
        switch self {
        case .noBudget, .ok: return 0
        case .near: return 1
        case .over: return 2
        }
    }
}
