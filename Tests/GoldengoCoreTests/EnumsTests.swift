import XCTest
@testable import GoldengoCore

final class EnumsTests: XCTestCase {
    func test_transactionKind_rawValues() {
        XCTAssertEqual(TransactionKind.expense.rawValue, "expense")
        XCTAssertEqual(TransactionKind.allCases.count, 3)
    }

    func test_expenseSource_rawValues() {
        XCTAssertEqual(ExpenseSource.manual.rawValue, "manual")
        XCTAssertEqual(Set(ExpenseSource.allCases), [.manual, .imported, .crypto])
    }
}
