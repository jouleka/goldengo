import XCTest
@testable import GoldengoCore

final class ExchangeRateAPIResponseTests: XCTestCase {
    // The real API shape (subset): result/base_code/time_last_update_unix/rates → RateTable.
    func test_decode_mapsToRateTable_usingUnixTimestamp() throws {
        // 1_780_444_800 == 2026-06-03 00:00:00 UTC (verified via `date -u`).
        let json = """
        {"result":"success","base_code":"USD","time_last_update_unix":1780444800,
         "time_last_update_utc":"Wed, 03 Jun 2026 00:00:00 +0000",
         "rates":{"USD":1,"EUR":0.859836,"ALL":81.946489}}
        """
        let dto = try JSONDecoder().decode(ExchangeRateAPIResponse.self, from: Data(json.utf8))
        let table = try XCTUnwrap(dto.toRateTable())
        XCTAssertEqual(table.base, CurrencyCode("USD"))
        XCTAssertEqual(table.rates["ALL"], Decimal(string: "81.946489")!)
        XCTAssertEqual(table.asOf, Date(timeIntervalSince1970: 1_780_444_800))
    }

    // Falls back to the RFC1123 UTC string if the unix field is absent.
    func test_decode_fallsBackToUtcStringWhenNoUnix() throws {
        let json = """
        {"result":"success","base_code":"USD",
         "time_last_update_utc":"Wed, 03 Jun 2026 00:02:31 +0000",
         "rates":{"USD":1,"EUR":0.86}}
        """
        let dto = try JSONDecoder().decode(ExchangeRateAPIResponse.self, from: Data(json.utf8))
        let table = try XCTUnwrap(dto.toRateTable())
        XCTAssertEqual(table.asOf.timeIntervalSince1970, 1_780_444_951, accuracy: 1) // 2026-06-03 00:02:31Z
    }

    // A non-success payload yields nil (caller keeps the prior cache).
    func test_decode_nonSuccessYieldsNil() throws {
        let json = #"{"result":"error","base_code":"USD","rates":{}}"#
        let dto = try JSONDecoder().decode(ExchangeRateAPIResponse.self, from: Data(json.utf8))
        XCTAssertNil(dto.toRateTable())
    }
}
