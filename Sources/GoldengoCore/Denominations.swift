import Foundation

/// Bank of Albania circulation denominations (10,000-lek note issued 2021), plus the euro
/// tables for the multi-currency wallet (GOL-95 v2; cents ignored — pocket cents don't move
/// the books). Currencies without a table fall back to typing the balance.
public enum Denominations {
    public static let lekNotes: [Int] = [10000, 5000, 2000, 1000, 500, 200]
    public static let lekCoins: [Int] = [100, 50, 20, 10, 5, 1]
    public static let euroNotes: [Int] = [500, 200, 100, 50, 20, 10, 5]
    public static let euroCoins: [Int] = [2, 1]

    public static func notes(for currency: CurrencyCode) -> [Int] {
        if currency == .all { return lekNotes }
        if currency == .eur { return euroNotes }
        return []
    }
    public static func coins(for currency: CurrencyCode) -> [Int] {
        if currency == .all { return lekCoins }
        if currency == .eur { return euroCoins }
        return []
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
