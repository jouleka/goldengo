import XCTest
@testable import GoldengoCore

final class CurrencyCodeMetadataTests: XCTestCase {
    // ISO 4217 zero-decimal currencies must render with no minor unit.
    func test_fractionDigits_isoZeroDecimalCurrencies() {
        XCTAssertEqual(CurrencyCode("JPY").fractionDigits, 0)
        XCTAssertEqual(CurrencyCode("KRW").fractionDigits, 0)
        XCTAssertEqual(CurrencyCode("ISK").fractionDigits, 0)
        XCTAssertEqual(CurrencyCode("XOF").fractionDigits, 0)
    }

    // ISO 4217 three-decimal currencies (Gulf dinars etc.).
    func test_fractionDigits_threeDecimalCurrencies() {
        XCTAssertEqual(CurrencyCode("BHD").fractionDigits, 3)
        XCTAssertEqual(CurrencyCode("KWD").fractionDigits, 3)
        XCTAssertEqual(CurrencyCode("TND").fractionDigits, 3)
    }

    // Lek is displayed whole — a deliberate product override of ISO 4217 (which says 2).
    func test_fractionDigits_lekStaysZeroByProductChoice() {
        XCTAssertEqual(CurrencyCode.all.fractionDigits, 0)
    }

    // Everything else, including unknown codes, defaults to 2.
    func test_fractionDigits_defaultsToTwo() {
        XCTAssertEqual(CurrencyCode.eur.fractionDigits, 2)
        XCTAssertEqual(CurrencyCode("USD").fractionDigits, 2)
        XCTAssertEqual(CurrencyCode("ZZZ").fractionDigits, 2)
    }

    func test_symbol_knownAndUnknownFallback() {
        XCTAssertEqual(CurrencyCode("USD").symbol, "$")
        XCTAssertEqual(CurrencyCode("JPY").symbol, "¥")
        XCTAssertEqual(CurrencyCode.all.symbol, "ALL")  // lek shows its ISO code, not the ambiguous "L"
        XCTAssertEqual(CurrencyCode("ZZZ").symbol, "ZZZ") // unknown → ISO code
        // Ambiguous glyphs fall back to the ISO code: ¥ is shared by yen and renminbi, so CNY
        // must NOT render as ¥ (same rule that excludes CAD/AUD/SGD's "$").
        XCTAssertEqual(CurrencyCode("CNY").symbol, "CNY")
    }

    func test_popular_startsWithLekAndEuro_andHasNoDuplicates() {
        XCTAssertEqual(Array(CurrencyCode.popular.prefix(2)), [.all, .eur])
        XCTAssertEqual(Set(CurrencyCode.popular).count, CurrencyCode.popular.count)
    }
}
