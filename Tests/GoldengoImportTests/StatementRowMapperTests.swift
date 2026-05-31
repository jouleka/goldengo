import XCTest
import GoldengoCore
@testable import GoldengoImport

final class StatementRowMapperTests: XCTestCase {
    private let mapping = ColumnMapping(dateIndex: 0, amount: .signed(index: 1), merchantIndex: 2,
                                        externalIDIndex: 3, dateFormats: ["dd.MM.yyyy"],
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

    func test_debitCreditColumns_mapDirectionCorrectly() throws {
        let m = ColumnMapping(dateIndex: 0, amount: .debitCredit(debit: 3, credit: 4), merchantIndex: 1,
                              externalIDIndex: nil, dateFormats: ["dd/MM/yy"], decimalSeparator: ".",
                              groupingSeparator: ",", currency: .all)
        let debit = try XCTUnwrap(StatementRowMapper.map(row: ["29/05/26","BASHKIA TIRANA","29/05/26","-500.00","",""], using: m))
        XCTAssertEqual(debit.kind, .expense); XCTAssertEqual(debit.amount, 500)
        let credit = try XCTUnwrap(StatementRowMapper.map(row: ["29/05/26","SALARY","29/05/26","","260,000.00",""], using: m))
        XCTAssertEqual(credit.kind, .income); XCTAssertEqual(credit.amount, 260000)
    }
}
