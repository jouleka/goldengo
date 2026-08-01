import XCTest
@testable import GoldengoCore

final class EnumsTests: XCTestCase {
    func test_transactionKind_rawValues() {
        XCTAssertEqual(TransactionKind.expense.rawValue, "expense")
        // Raw values are PERSISTED in kindRaw — this pins them so a rename can't corrupt data.
        XCTAssertEqual(TransactionKind.lent.rawValue, "lent")
        XCTAssertEqual(TransactionKind.repayment.rawValue, "repayment")
        XCTAssertEqual(TransactionKind.refund.rawValue, "refund")
        XCTAssertEqual(TransactionKind.allCases.count, 6)
    }

    func test_expenseSource_rawValues() {
        XCTAssertEqual(ExpenseSource.manual.rawValue, "manual")
        XCTAssertEqual(Set(ExpenseSource.allCases), [.manual, .imported, .crypto, .automatic])
    }
}
