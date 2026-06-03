import Foundation

/// Pure, dependency-free converter over a `RateTable`. Returns UNROUNDED `Decimal` so callers can
/// sum many conversions and round once at display time (avoids accumulation error).
public struct CurrencyConverter: Sendable {
    public let table: RateTable

    public init(table: RateTable) {
        self.table = table
    }

    public enum ConversionError: Error, Equatable {
        case missingRate(CurrencyCode)
    }

    /// Cross-rate through the base: `(amount * rate[to]) / rate[from]`. Same-currency is identity.
    public func convert(_ amount: Decimal, from: CurrencyCode, to: CurrencyCode) throws -> Decimal {
        if from == to { return amount }
        guard let rateFrom = table.rates[from.rawValue] else { throw ConversionError.missingRate(from) }
        guard let rateTo = table.rates[to.rawValue] else { throw ConversionError.missingRate(to) }
        return (amount * rateTo) / rateFrom
    }

    /// Convenience: convert a `Money` and re-tag it with the target currency.
    public func convert(_ money: Money, to: CurrencyCode) throws -> Money {
        Money(amount: try convert(money.amount, from: money.currency, to: to), currency: to)
    }

    /// True when the table is older than `maxAge` relative to `now`.
    public func isStale(asOf now: Date, maxAge: TimeInterval) -> Bool {
        now.timeIntervalSince(table.asOf) > maxAge
    }
}
