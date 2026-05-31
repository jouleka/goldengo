import XCTest
import GoldengoCore
@testable import GoldengoImport

final class StatementRowMapperTests: XCTestCase {
    private let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, merchantIndex: 2,
                                        externalIDIndex: 3, dateFormat: "dd.MM.yyyy",
                                        decimalSeparator: ",", groupingSeparator: ".",
                                        currency: .all)

    func test_maps_debitRowToExpense_absAmount() throws {
        let tx = try XCTUnwrap(StatementRowMapper.map(row: ["30.05.2026","-1.500,00","SPAR TIRANA","tx1"], using: mapping))
        XCTAssertEqual(tx.kind, .expense)
        XCTAssertEqual(tx.amount, Decimal(string: "1500.00"))
        XCTAssertEqual(tx.rawMerchant, "SPAR TIRANA")
        XCTAssertEqual(tx.externalID, "tx1")
        XCTAssertEqual(tx.dedupeKey, "ext:tx1")
    }
    func test_maps_creditRowToIncome() throws {
        let tx = try XCTUnwrap(StatementRowMapper.map(row: ["01.05.2026","2.000,00","SALARY","tx2"], using: mapping))
        XCTAssertEqual(tx.kind, .income)
        XCTAssertEqual(tx.amount, 2000)
    }
    func test_returnsNil_forUnparseableDateOrAmount() {
        XCTAssertNil(StatementRowMapper.map(row: ["Date","Amount","Desc","ID"], using: mapping)) // header
        XCTAssertNil(StatementRowMapper.map(row: ["x","y","z","w"], using: mapping))
    }
}
