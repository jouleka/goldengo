import Foundation

/// Pure wallet arithmetic (GOL-95). The store maps records → flows (it owns the
/// manual/transfer/prefix selection rules); this stays testable math.
public enum CashLedger {
    public struct Flow: Equatable, Sendable {
        public var amount: Decimal      // positive magnitude
        public var isInflow: Bool       // ATM transfer / cash income vs cash spend
        public init(amount: Decimal, isInflow: Bool) { self.amount = amount; self.isInflow = isInflow }
    }

    /// Baseline (the latest count's total) plus inflows, minus outflows. Never clamped:
    /// a negative expectation is real signal the next count's drift will surface.
    public static func expected(baselineTotal: Decimal, flows: [Flow]) -> Decimal {
        flows.reduce(baselineTotal) { $0 + ($1.isInflow ? $1.amount : -$1.amount) }
    }

    /// counted − expected. Negative = cash slipped by unlogged.
    public static func drift(counted: Decimal, expected: Decimal) -> Decimal {
        counted - expected
    }
}
