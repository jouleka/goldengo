import XCTest
@testable import GoldengoData

final class PurchaseImpactTests: XCTestCase {
    func test_impactProtectsGoalsAndCommitmentsAlreadyReservedBySafeToSpend() {
        let horizon = Date.now.addingTimeInterval(10 * 86_400)
        let safe = SafeToSpendSnapshot(available: 1_000, reservedForGoals: 200,
                                       upcomingCommitments: 300, safeTotal: 500,
                                       perDay: 50, horizonDate: horizon, dayCount: 10, usesWallet: true)
        let result = safe.impact(of: 150, on: .now)
        XCTAssertEqual(result.fit, .comfortable)
        XCTAssertEqual(result.safeBefore, 500)
        XCTAssertEqual(result.safeAfter, 350)
        XCTAssertEqual(result.shortfall, 0)
    }

    func test_impactSurfacesShortfallInsteadOfNegativeSafeMoney() {
        let safe = SafeToSpendSnapshot(available: 400, reservedForGoals: 100,
                                       upcomingCommitments: 100, safeTotal: 200,
                                       perDay: 20, horizonDate: .now.addingTimeInterval(10 * 86_400),
                                       dayCount: 10, usesWallet: true)
        let result = safe.impact(of: 275, on: .now)
        XCTAssertEqual(result.fit, .notYet)
        XCTAssertEqual(result.safeAfter, 0)
        XCTAssertEqual(result.shortfall, 75)
    }
}
