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

    private static let notesByCode: [String: [Int]] = [
        "ALL": lekNotes,
        "EUR": euroNotes,
        "USD": [100, 50, 20, 10, 5, 2, 1],
        "GBP": [50, 20, 10, 5],
        "CHF": [1000, 200, 100, 50, 20, 10],
        "TRY": [200, 100, 50, 20, 10, 5],
    ]
    private static let coinsByCode: [String: [Int]] = [
        "ALL": lekCoins,
        "EUR": euroCoins,
        "GBP": [2, 1],
        "CHF": [5, 2, 1],
        "TRY": [1],
    ]

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
