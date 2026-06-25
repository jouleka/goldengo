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
        // A non-positive rate is corrupt data (a malformed feed) — treat it as missing rather than
        // dividing by it: Decimal ÷ 0 yields a NaN-flagged value that would silently poison sums.
        guard let rateFrom = table.rates[from.rawValue], rateFrom > 0 else { throw ConversionError.missingRate(from) }
        guard let rateTo = table.rates[to.rawValue], rateTo > 0 else { throw ConversionError.missingRate(to) }
        return (amount * rateTo) / rateFrom
    }

    /// Convenience: convert a `Money` and re-tag it with the target currency.
    public func convert(_ money: Money, to: CurrencyCode) throws -> Money {
        Money(amount: try convert(money.amount, from: money.currency, to: to), currency: to)
    }

    /// Convert each `Money` to `target` and sum, skipping any that can't convert (missing rate).
    public func sum(_ monies: [Money], to target: CurrencyCode) -> Decimal {
        monies.reduce(Decimal(0)) { acc, m in
            (try? convert(m, to: target)).map { acc + $0.amount } ?? acc
        }
    }

    /// True when the table is older than `maxAge` relative to `now`.
    public func isStale(asOf now: Date, maxAge: TimeInterval) -> Bool {
        now.timeIntervalSince(table.asOf) > maxAge
    }
}
