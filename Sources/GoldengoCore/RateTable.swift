import Foundation

/// A snapshot of exchange rates relative to a base currency, with the time they were published.
/// `Decimal` (not `Double`) so cached/seeded values carry no floating-point drift.
public struct RateTable: Sendable, Equatable, Codable {
    public let base: CurrencyCode          // e.g. USD
    public let rates: [String: Decimal]    // units of <code> per 1 base; base maps to 1
    public let asOf: Date                  // when these rates were published

    public init(base: CurrencyCode, rates: [String: Decimal], asOf: Date) {
        self.base = base
        self.rates = rates
        self.asOf = asOf
    }
}
