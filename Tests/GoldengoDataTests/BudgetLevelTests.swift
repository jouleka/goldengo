import XCTest
import Foundation
@testable import GoldengoData

final class BudgetLevelTests: XCTestCase {
    func test_noBudget_whenCapNilOrZero() {
        XCTAssertEqual(BudgetLevel.forSpend(500, cap: nil), .noBudget)
        XCTAssertEqual(BudgetLevel.forSpend(500, cap: 0), .noBudget)
    }
    func test_ok_belowNearLine() {
        XCTAssertEqual(BudgetLevel.forSpend(0, cap: 100), .ok)
        XCTAssertEqual(BudgetLevel.forSpend(84, cap: 100), .ok)   // 84% < 85%
    }
    func test_near_atOrAbove85_below100() {
        XCTAssertEqual(BudgetLevel.forSpend(85, cap: 100), .near)  // exactly 85%
        XCTAssertEqual(BudgetLevel.forSpend(99, cap: 100), .near)
    }
    func test_over_atOrAbove100() {
        XCTAssertEqual(BudgetLevel.forSpend(100, cap: 100), .over) // exactly 100%
        XCTAssertEqual(BudgetLevel.forSpend(130, cap: 100), .over)
    }
    func test_rankOrders_okNearOver() {
        XCTAssertTrue(BudgetLevel.ok.rank < BudgetLevel.near.rank)
        XCTAssertTrue(BudgetLevel.near.rank < BudgetLevel.over.rank)
    }
}
