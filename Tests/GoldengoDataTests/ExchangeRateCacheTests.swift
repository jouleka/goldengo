import XCTest
import GoldengoCore
@testable import GoldengoData

final class ExchangeRateCacheTests: XCTestCase {
    // A dedicated suite so the test never touches the real App Group defaults.
    private let suite = "test.goldengo.fxcache"

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func test_load_isNilBeforeAnySave() {
        let cache = ExchangeRateCache(suiteName: suite)
        XCTAssertNil(cache.load())
    }

    func test_saveThenLoad_roundTripsTheTable() {
        let cache = ExchangeRateCache(suiteName: suite)
        let table = RateTable(base: CurrencyCode("USD"),
                              rates: ["USD": 1, "ALL": Decimal(string: "81.95")!],
                              asOf: Date(timeIntervalSince1970: 1_780_444_800))
        cache.save(table)
        XCTAssertEqual(cache.load(), table)
    }
}
