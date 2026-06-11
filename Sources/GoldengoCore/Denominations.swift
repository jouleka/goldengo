import Foundation

/// Circulation denominations for the wallet's optional note counter (GOL-95 v2), in WHOLE
/// major units only — sub-unit coins (cents, pence, rappen) can't be tallied and don't move
/// pocket truth. Only VERIFIED tables ship: an invented note value would corrupt the very
/// number the counter exists to make trustworthy, so unlisted currencies are typed, not
/// counted. (Lek: Bank of Albania, 10,000-lek note issued 2021.)
public enum Denominations {
    public static let lekNotes: [Int] = [10000, 5000, 2000, 1000, 500, 200]
    public static let lekCoins: [Int] = [100, 50, 20, 10, 5, 1]
    public static let euroNotes: [Int] = [500, 200, 100, 50, 20, 10, 5]
    public static let euroCoins: [Int] = [2, 1]

    // Dedupe rule: a value circulating as BOTH note and coin (RSD 20, HKD 10, MXN 20, …) is
    // listed once, under notes — the counter cares about the value, not the material, and a
    // duplicate would collide ForEach identities in the grid.
    // Verified 2026-06: DKK 1000-kr invalid since 2025-05-31 (Danmarks Nationalbank); INR 2000
    // withdrawn 2023 (RBI); RSD/MKD/SAR sets per NBS/NBRNM/SAMA.
    private static let notesByCode: [String: [Int]] = [
        "ALL": lekNotes,
        "EUR": euroNotes,
        "USD": [100, 50, 20, 10, 5, 2, 1],
        "GBP": [50, 20, 10, 5],
        "CHF": [1000, 200, 100, 50, 20, 10],
        "TRY": [200, 100, 50, 20, 10, 5],
        "JPY": [10000, 5000, 2000, 1000],
        "CNY": [100, 50, 20, 10, 5, 1],
        "CAD": [100, 50, 20, 10, 5],
        "AUD": [100, 50, 20, 10, 5],
        "NZD": [100, 50, 20, 10, 5],
        "SEK": [1000, 500, 200, 100, 50, 20],
        "NOK": [1000, 500, 200, 100, 50],
        "DKK": [500, 200, 100, 50],
        "PLN": [500, 200, 100, 50, 20, 10],
        "CZK": [5000, 2000, 1000, 500, 200, 100],
        "HUF": [20000, 10000, 5000, 2000, 1000, 500],
        "RON": [500, 200, 100, 50, 20, 10, 5, 1],
        "BGN": [100, 50, 20, 10, 5],
        "RSD": [5000, 2000, 1000, 500, 200, 100, 50, 20, 10],
        "MKD": [2000, 1000, 500, 200, 100, 50, 10],
        "AED": [1000, 500, 200, 100, 50, 20, 10, 5],
        "SAR": [500, 200, 100, 50, 20, 10, 5, 1],
        "INR": [500, 200, 100, 50, 20, 10],
        "KRW": [50000, 10000, 5000, 1000],
        "SGD": [1000, 100, 50, 10, 5, 2],
        "HKD": [1000, 500, 100, 50, 20, 10],
        "MXN": [1000, 500, 200, 100, 50, 20],
        "BRL": [200, 100, 50, 20, 10, 5, 2],
        "ZAR": [200, 100, 50, 20, 10],
    ]
    private static let coinsByCode: [String: [Int]] = [
        "ALL": lekCoins,
        "EUR": euroCoins,
        "GBP": [2, 1],
        "CHF": [5, 2, 1],
        "TRY": [1],
        "JPY": [500, 100, 50, 10, 5, 1],
        "CAD": [2, 1],
        "AUD": [2, 1],
        "NZD": [2, 1],
        "SEK": [10, 5, 2, 1],
        "NOK": [20, 10, 5, 1],
        "DKK": [20, 10, 5, 2, 1],
        "PLN": [5, 2, 1],
        "CZK": [50, 20, 10, 5, 2, 1],
        "HUF": [200, 100, 50, 20, 10, 5],
        "BGN": [2, 1],
        "RSD": [5, 2, 1],
        "MKD": [5, 2, 1],
        "AED": [1],
        "SAR": [2],
        "INR": [5, 2, 1],
        "KRW": [500, 100, 50, 10],
        "SGD": [1],
        "HKD": [5, 2, 1],
        "MXN": [10, 5, 2, 1],
        "BRL": [1],
        "ZAR": [5, 2, 1],
    ]

    /// Currency codes with a verified counter table (for tests and future surfaces).
    public static var counterSupported: [String] { notesByCode.keys.sorted() }

    public static func notes(for currency: CurrencyCode) -> [Int] {
        notesByCode[currency.rawValue] ?? []
    }
    public static func coins(for currency: CurrencyCode) -> [Int] {
        coinsByCode[currency.rawValue] ?? []
    }
}

/// What's physically in the wallet: denomination → how many. Codable for the
/// WalletCount storage blob (GOL-95).
public struct DenominationTally: Codable, Equatable, Sendable {
    public var counts: [Int: Int] = [:]
    public init() {}
    public var total: Decimal {
        counts.reduce(Decimal(0)) { $0 + Decimal($1.key * $1.value) }
    }
}
