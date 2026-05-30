public struct CurrencyCode: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public static let all = CurrencyCode("ALL")   // Albanian lek
    public static let eur = CurrencyCode("EUR")

    /// Display symbol; falls back to the raw code (e.g. crypto tickers).
    public var symbol: String {
        switch rawValue {
        case "ALL": return "L"
        case "EUR": return "€"
        default:    return rawValue
        }
    }

    /// Currencies with no minor unit in everyday display (lek is shown without decimals).
    public var fractionDigits: Int {
        rawValue == "ALL" ? 0 : 2
    }
}
