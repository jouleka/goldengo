import XCTest
@testable import GoldengoCore

final class RateTableTests: XCTestCase {
    // The cache serializes RateTable to JSON; encode→decode must preserve everything exactly,
    // including Decimal precision (so cached rates don't drift).
    func test_codableRoundTrip_preservesBaseRatesAndDate() throws {
        let table = RateTable(
            base: CurrencyCode("USD"),
            rates: ["USD": 1, "EUR": Decimal(string: "0.859836")!, "ALL": Decimal(string: "81.946489")!],
            asOf: Date(timeIntervalSince1970: 1_748_908_800)
        )
        let data = try JSONEncoder().encode(table)
        let decoded = try JSONDecoder().decode(RateTable.self, from: data)
        XCTAssertEqual(decoded, table)
        XCTAssertEqual(decoded.rates["ALL"], Decimal(string: "81.946489")!)
    }
}
