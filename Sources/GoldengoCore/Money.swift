import Foundation

public struct Money: Hashable, Sendable {
    public var amount: Decimal
    public var currency: CurrencyCode

    public init(amount: Decimal, currency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
    }

    /// Deterministic formatting (explicit separators) so it is locale-independent and testable.
    public func formatted() -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = currency.fractionDigits
        f.maximumFractionDigits = currency.fractionDigits
        let number = NSDecimalNumber(decimal: amount)
        let body = f.string(from: number) ?? "\(amount)"
        return "\(currency.symbol) \(body)"
    }
}
