import XCTest
@testable import GoldengoCore

final class CurrencyCatalogTests: XCTestCase {
    private func table(_ codes: [String]) -> RateTable {
        var rates: [String: Decimal] = [:]
        for c in codes { rates[c] = 1 }
        return RateTable(base: CurrencyCode("USD"), rates: rates, asOf: Date(timeIntervalSince1970: 0))
    }

    // selectable() exposes spendable currencies and drops non-currency codes (metals, SDR).
    func test_selectable_excludesNonCurrencies() {
        let codes = CurrencyCatalog.selectable(from: table(["USD", "EUR", "ALL", "XAU", "XDR"]))
            .map(\.rawValue)
        XCTAssertTrue(codes.contains("USD"))
        XCTAssertTrue(codes.contains("ALL"))
        XCTAssertFalse(codes.contains("XAU"))
        XCTAssertFalse(codes.contains("XDR"))
    }

    // Empty query returns the input unchanged (no filtering).
    func test_filter_emptyQuery_returnsAll() {
        let input = [CurrencyCode("USD"), CurrencyCode("EUR")]
        XCTAssertEqual(CurrencyCatalog.filter(input, query: "  ", name: { _ in "" }), input)
    }

    // Matches by ISO code, case-insensitively.
    func test_filter_matchesByCode_caseInsensitive() {
        let input = [CurrencyCode("USD"), CurrencyCode("EUR"), CurrencyCode("ALL")]
        let out = CurrencyCatalog.filter(input, query: "eur", name: { _ in "" }).map(\.rawValue)
        XCTAssertEqual(out, ["EUR"])
    }

    // Matches by display name (injected), even when the code doesn't contain the query.
    func test_filter_matchesByName() {
        let input = [CurrencyCode("ALL"), CurrencyCode("EUR")]
        let names = ["ALL": "Albanian Lek", "EUR": "Euro"]
        let out = CurrencyCatalog.filter(input, query: "lek", name: { names[$0.rawValue] ?? "" }).map(\.rawValue)
        XCTAssertEqual(out, ["ALL"])
    }
}
