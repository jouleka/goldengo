import Foundation
import GoldengoCore

/// App-Group cache for the latest `RateTable`, mirroring `SharedSummary`'s UserDefaults pattern.
public struct ExchangeRateCache {
    private let defaults: UserDefaults
    private static let key = "exchangeRateTable"

    public init(suiteName: String? = SharedSummary.appGroupID) {
        defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The last cached table, or nil if nothing has been fetched yet.
    public func load() -> RateTable? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(RateTable.self, from: data)
    }

    public func save(_ table: RateTable) {
        guard let data = try? JSONEncoder().encode(table) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
