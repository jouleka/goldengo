import XCTest
import GoldengoCore

final class DenominationsTests: XCTestCase {
    func test_lekTables_matchBankOfAlbania() {
        XCTAssertEqual(Denominations.lekNotes, [10000, 5000, 2000, 1000, 500, 200])
        XCTAssertEqual(Denominations.lekCoins, [100, 50, 20, 10, 5, 1])
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
