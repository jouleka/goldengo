import XCTest
@testable import GoldengoCore

final class ExpenseSourceTests: XCTestCase {
    func test_automatic_caseExistsWithStableRawValue() {
        XCTAssertEqual(ExpenseSource.automatic.rawValue, "automatic")
        XCTAssertTrue(ExpenseSource.allCases.contains(.automatic))
    }
}
