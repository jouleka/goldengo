import Foundation

/// Bank of Albania circulation denominations (10,000-lek note issued 2021).
public enum Denominations {
    public static let lekNotes: [Int] = [10000, 5000, 2000, 1000, 500, 200]
    public static let lekCoins: [Int] = [100, 50, 20, 10, 5, 1]
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
