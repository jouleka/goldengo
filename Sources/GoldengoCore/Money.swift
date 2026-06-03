import Foundation

public struct Money: Hashable, Sendable {
    public var amount: Decimal
    public var currency: CurrencyCode

    public init(amount: Decimal, currency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
    }

    /// Display-only formatting: locale-independent (explicit separators), with the
    /// magnitude formatted and the sign placed before the symbol (e.g. "-L 1,500").
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

    private func signAndBody() -> (sign: String, body: String) {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        f.usesGroupingSeparator = true
        f.roundingMode = .halfUp
        f.minimumFractionDigits = currency.fractionDigits
        f.maximumFractionDigits = currency.fractionDigits
        let magnitude = NSDecimalNumber(decimal: abs(amount))
        let body = f.string(from: magnitude) ?? "\(abs(amount))"
        return (amount < 0 ? "-" : "", body)
    }
}
