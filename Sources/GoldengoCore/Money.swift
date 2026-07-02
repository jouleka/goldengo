import Foundation

public struct Money: Hashable, Sendable {
    public var amount: Decimal
    public var currency: CurrencyCode

    public init(amount: Decimal, currency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
    }

    /// Display-only formatting: locale-independent (explicit separators), with the
    /// magnitude formatted and the sign placed before the symbol (e.g. "-ALL 1,500").
    /// Rounding is explicit and lossy — never use this output for serialization or keys.
    public func formatted() -> String {
        let (sign, body) = signAndBody()
        return "\(sign)\(currency.symbol) \(body)"
    }

    /// The signed magnitude WITHOUT the currency symbol (e.g. "-1,383.98"), for layouts that render
    /// the currency separately (e.g. a tappable currency control beside the amount).
    public func amountText() -> String {
        let (sign, body) = signAndBody()
        return "\(sign)\(body)"
    }

    /// The amount rounded to this currency's display precision (`.plain`, matching `formatted()`).
    /// For prefills and comparisons against what the user can SEE — lossy, never for ledger math.
    public func roundedAmount() -> Decimal {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, currency.fractionDigits, .plain)
        return rounded
    }

    private func signAndBody() -> (sign: String, body: String) {
        let digits = currency.fractionDigits
        let magnitude = abs(amount)
        let body = Money.format(magnitude, fractionDigits: digits)
        // Derive the sign from the ROUNDED magnitude, not the raw amount: a sub-unit negative residue
        // (e.g. -0.004 left by a cross-rate division) rounds to "0.00"/"0", and a minus on a zero body
        // ("-€ 0.00") is wrong. Emit the sign only when the displayed magnitude is non-zero. `.plain`
        // (round half away from zero) matches the formatter's `.halfUp` on a non-negative magnitude.
        var rounded = Decimal()
        var mag = magnitude
        NSDecimalRound(&rounded, &mag, digits, .plain)
        let sign = (amount < 0 && rounded != 0) ? "-" : ""
        return (sign, body)
    }

    /// Configured `NumberFormatter`s are expensive to build, and an amount is formatted once per
    /// SwiftUI body pass (Home/Recent render dozens), so reuse one per fraction-digit count. The
    /// config varies only by min/max fraction digits. `NumberFormatter` is not `Sendable` and
    /// `string(from:)` isn't guaranteed concurrency-safe, so the lock is held across the format call —
    /// still far cheaper than allocating + configuring a fresh formatter on every call.
    nonisolated(unsafe) private static var formatters: [Int: NumberFormatter] = [:]
    private static let formattersLock = NSLock()

    private static func format(_ value: Decimal, fractionDigits: Int) -> String {
        formattersLock.lock()
        defer { formattersLock.unlock() }
        let f: NumberFormatter
        if let cached = formatters[fractionDigits] {
            f = cached
        } else {
            f = NumberFormatter()
            f.numberStyle = .decimal
            f.groupingSeparator = ","
            f.decimalSeparator = "."
            f.usesGroupingSeparator = true
            f.roundingMode = .halfUp
            f.minimumFractionDigits = fractionDigits
            f.maximumFractionDigits = fractionDigits
            formatters[fractionDigits] = f
        }
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}
