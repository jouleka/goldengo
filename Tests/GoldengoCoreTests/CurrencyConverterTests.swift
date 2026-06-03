import XCTest
@testable import GoldengoCore

final class CurrencyConverterTests: XCTestCase {
    // USD-base table: 1 USD = 100 ALL = 0.9 EUR.
    private func table(asOf: Date = Date(timeIntervalSince1970: 1_000_000)) -> RateTable {
        RateTable(base: CurrencyCode("USD"),
                  rates: ["USD": 1, "ALL": 100, "EUR": Decimal(string: "0.9")!],
                  asOf: asOf)
    }

    // Same-currency conversion is identity — even when that currency is absent from the table.
    func test_sameCurrency_returnsAmountUnchanged() throws {
        let thin = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1], asOf: Date())
        let c = CurrencyConverter(table: thin)
        XCTAssertEqual(try c.convert(42, from: .eur, to: .eur), 42)
    }

    // Cross-rate goes through the base: 100 ALL → EUR = 100 * 0.9 / 100 = 0.9.
    func test_crossRate_isComputedThroughBase() throws {
        let c = CurrencyConverter(table: table())
        XCTAssertEqual(try c.convert(100, from: .all, to: .eur), Decimal(string: "0.9")!)
    }

    // Conversion must be reversible within rounding tolerance (catches inverted ratios).
    func test_roundTrip_returnsApproximatelyOriginal() throws {
        let c = CurrencyConverter(table: table())
        let there = try c.convert(1234, from: .all, to: .eur)
        let back = try c.convert(there, from: .eur, to: .all)
        XCTAssertLessThan(abs(back - 1234), Decimal(string: "0.0001")!)
    }

    // A missing rate must throw — we never silently fabricate a rate.
    func test_missingRate_throws() {
        let c = CurrencyConverter(table: table())
        XCTAssertThrowsError(try c.convert(1, from: CurrencyCode("XYZ"), to: .eur)) { error in
            XCTAssertEqual(error as? CurrencyConverter.ConversionError, .missingRate(CurrencyCode("XYZ")))
        }
    }

    // Money convenience overload tags the result with the target currency.
    func test_convertMoney_setsTargetCurrency() throws {
        let c = CurrencyConverter(table: table())
        let out = try c.convert(Money(amount: 100, currency: .all), to: .eur)
        XCTAssertEqual(out, Money(amount: Decimal(string: "0.9")!, currency: .eur))
    }

    // Staleness flips exactly at maxAge past asOf.
    func test_isStale_boundary() {
        let asOf = Date(timeIntervalSince1970: 1_000_000)
        let c = CurrencyConverter(table: table(asOf: asOf))
        XCTAssertFalse(c.isStale(asOf: asOf.addingTimeInterval(3599), maxAge: 3600))
        XCTAssertTrue(c.isStale(asOf: asOf.addingTimeInterval(3601), maxAge: 3600))
    }
}
