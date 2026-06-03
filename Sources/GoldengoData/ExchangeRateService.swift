import Foundation
import OSLog
import GoldengoCore

/// Refreshes the App-Group rate cache from ExchangeRate-API's free, key-less open endpoint.
/// Fully offline-safe: any failure leaves the existing cache untouched and never throws to callers.
public struct ExchangeRateService: Sendable {
    private static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!
    private static let log = Logger(subsystem: "com.goldengo.app", category: "fx")

    public init() {}

    /// Fetches fresh rates only when the cache is missing or older than `maxAge`.
    public func refreshIfNeeded(now: Date = .now,
                                maxAge: TimeInterval = 12 * 3600,
                                suiteName: String? = SharedSummary.appGroupID) async {
        let cache = ExchangeRateCache(suiteName: suiteName)
        if let existing = cache.load(), now.timeIntervalSince(existing.asOf) < maxAge {
            Self.log.debug("FX cache fresh (asOf \(existing.asOf, privacy: .public)); skipping fetch")
            return
        }
        guard let table = await fetchLatest() else { return }
        cache.save(table)
        Self.log.info("FX cache updated: \(table.rates.count, privacy: .public) rates, asOf \(table.asOf, privacy: .public)")
    }

    /// Single GET → DTO → RateTable. Returns nil on any network/HTTP/decode failure.
    func fetchLatest() async -> RateTable? {
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.endpoint)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                Self.log.error("FX fetch non-200")
                return nil
            }
            return try JSONDecoder().decode(ExchangeRateAPIResponse.self, from: data).toRateTable()
        } catch {
            Self.log.error("FX fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
