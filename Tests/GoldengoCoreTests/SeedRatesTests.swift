import XCTest
@testable import GoldengoCore

final class SeedRatesTests: XCTestCase {
    // The bundled seed must always be usable so first-run-while-offline never crashes.
    func test_seedDecodes_hasManyCurrencies_andConverts() throws {
        let table = SeedRates.table
        XCTAssertEqual(table.base, CurrencyCode("USD"))
        XCTAssertGreaterThan(table.rates.count, 100) // real snapshot carries ~162 codes
        XCTAssertNotNil(table.rates["ALL"])
        XCTAssertNotNil(table.rates["EUR"])
        // Offline conversion path works end-to-end.
        let eur = try CurrencyConverter(table: table).convert(1000, from: .all, to: .eur)
        XCTAssertGreaterThan(eur, 0)
    }
}
