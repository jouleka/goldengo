import XCTest
import GoldengoCore
@testable import GoldengoData

final class ExchangeRateServiceTests: XCTestCase {
    private let suite = "test.goldengo.fxservice"

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func table(asOf: Date, eur: String) -> RateTable {
        RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "EUR": Decimal(string: eur)!], asOf: asOf)
    }

    // A fresh cache must NOT trigger a network fetch — we don't hammer the API on every launch.
    func test_skipsFetch_whenCacheIsFresh() async {
        let cache = ExchangeRateCache(suiteName: suite)
        cache.save(table(asOf: Date(timeIntervalSince1970: 1000), eur: "0.90"))
        let calls = CallCounter()
        let svc = ExchangeRateService(fetch: { await calls.bump(); return nil })

        // now is only 1h past asOf; maxAge 12h → fresh → skip.
        await svc.refreshIfNeeded(now: Date(timeIntervalSince1970: 1000 + 3600), maxAge: 12 * 3600, suiteName: suite)

        let n = await calls.value
        XCTAssertEqual(n, 0)
        // Cache is untouched (still the original 0.90).
        XCTAssertEqual(cache.load()?.rates["EUR"], Decimal(string: "0.90")!)
    }

    // A stale (or missing) cache must fetch and persist the fresh table.
    func test_fetchesAndSaves_whenCacheIsStale() async {
        let cache = ExchangeRateCache(suiteName: suite)
        cache.save(table(asOf: Date(timeIntervalSince1970: 1000), eur: "0.90"))
        let fetched = table(asOf: Date(timeIntervalSince1970: 99_999), eur: "0.86")
        let svc = ExchangeRateService(fetch: { fetched })

        // now is far past asOf → stale → fetch and save.
        await svc.refreshIfNeeded(now: Date(timeIntervalSince1970: 1_000_000), maxAge: 12 * 3600, suiteName: suite)

        XCTAssertEqual(cache.load(), fetched)
    }

    // A failed fetch (nil) on a stale cache must keep the prior cache — offline-safe, never throws.
    func test_keepsPriorCache_whenFetchFails() async {
        let cache = ExchangeRateCache(suiteName: suite)
        let original = table(asOf: Date(timeIntervalSince1970: 1000), eur: "0.90")
        cache.save(original)
        let svc = ExchangeRateService(fetch: { nil })

        await svc.refreshIfNeeded(now: Date(timeIntervalSince1970: 1_000_000), maxAge: 12 * 3600, suiteName: suite)

        XCTAssertEqual(cache.load(), original)
    }
}

private actor CallCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}
