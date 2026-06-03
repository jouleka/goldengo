public struct CurrencyCode: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public static let all = CurrencyCode("ALL")   // Albanian lek
    public static let eur = CurrencyCode("EUR")

    /// ISO 4217 currencies whose minor unit is 0 decimal digits (verified 2026-06-03 against
    /// the ISO 4217 table: en.wikipedia.org/wiki/ISO_4217).
    private static let isoZeroDigit: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF",
        "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
    ]
    /// ISO 4217 three-decimal currencies (verified 2026-06-03).
    private static let threeDigit: Set<String> = ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"]
    /// Display override: lek is shown without its (rarely used in practice) minor unit, matching
    /// the app's prior single-currency behaviour. ISO 4217 nominally assigns lek 2 digits.
    private static let displayZeroDigit: Set<String> = isoZeroDigit.union(["ALL"])

    /// Unambiguous display symbols; codes that share a glyph (e.g. CAD/AUD/SGD all "$") are left
    /// to fall back to the ISO code so the user is never shown an ambiguous symbol.
    private static let symbols: [String: String] = [
        "ALL": "L", "EUR": "€", "USD": "$", "GBP": "£", "JPY": "¥", "INR": "₹",
        "RUB": "₽", "TRY": "₺", "BRL": "R$", "KRW": "₩", "CHF": "Fr", "PLN": "zł", "THB": "฿",
        "VND": "₫", "UAH": "₴", "ILS": "₪", "PHP": "₱", "NGN": "₦", "ZAR": "R"
    ]

    /// Common currencies surfaced at the top of pickers (GOL-65/66). The full universe is "any
    /// code present in the rate table"; this is just the convenience shortcut group.
    public static let popular: [CurrencyCode] = [
        .all, .eur, CurrencyCode("USD"), CurrencyCode("GBP"), CurrencyCode("JPY"),
        CurrencyCode("CHF"), CurrencyCode("CAD"), CurrencyCode("AUD"), CurrencyCode("CNY"),
        CurrencyCode("INR"), CurrencyCode("AED"), CurrencyCode("TRY")
    ]

    /// Display symbol; falls back to the raw code (e.g. crypto tickers, ambiguous "$" currencies).
    public var symbol: String {
        Self.symbols[rawValue] ?? rawValue
    }

    /// Minor-unit decimal digits for everyday display. Default 2; ISO 4217 exceptions for 0/3;
    /// plus the lek display override.
    public var fractionDigits: Int {
        if Self.threeDigit.contains(rawValue) { return 3 }
        if Self.displayZeroDigit.contains(rawValue) { return 0 }
        return 2
    }
}
