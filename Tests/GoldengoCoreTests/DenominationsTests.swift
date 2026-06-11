import XCTest
import GoldengoCore

final class DenominationsTests: XCTestCase {
    func test_lekTables_matchBankOfAlbania() {
        XCTAssertEqual(Denominations.lekNotes, [10000, 5000, 2000, 1000, 500, 200])
        XCTAssertEqual(Denominations.lekCoins, [100, 50, 20, 10, 5, 1])
    }

    func test_verifiedTables_existOnlyWhereVerified() {
        // Verified circulation sets — whole major units only.
        XCTAssertEqual(Denominations.notes(for: CurrencyCode("USD")), [100, 50, 20, 10, 5, 2, 1])
        XCTAssertEqual(Denominations.coins(for: CurrencyCode("USD")), [], "US coins are all sub-dollar")
        XCTAssertEqual(Denominations.notes(for: CurrencyCode("GBP")), [50, 20, 10, 5])
        XCTAssertEqual(Denominations.coins(for: CurrencyCode("GBP")), [2, 1])
        XCTAssertEqual(Denominations.notes(for: CurrencyCode("CHF")), [1000, 200, 100, 50, 20, 10])
        XCTAssertEqual(Denominations.notes(for: CurrencyCode("TRY")), [200, 100, 50, 20, 10, 5])
        // Unverified currencies get NO table — typed, never counted with invented note values.
        XCTAssertTrue(Denominations.notes(for: CurrencyCode("JPY")).isEmpty)
        XCTAssertTrue(Denominations.coins(for: CurrencyCode("RSD")).isEmpty)
    }

    func test_tallyTotal() {
        var t = DenominationTally()
        t.counts = [1000: 2, 500: 1, 100: 3]
        XCTAssertEqual(t.total, 2800)
        XCTAssertEqual(DenominationTally().total, 0)
    }

    func test_tallyCodableRoundTrip() throws {
        var t = DenominationTally()
        t.counts = [5000: 1, 200: 4]
        let decoded = try JSONDecoder().decode(DenominationTally.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(decoded, t)
        XCTAssertEqual(decoded.total, 5800)
    }
}
