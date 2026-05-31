import XCTest
@testable import GoldengoData

final class SharedSummaryTests: XCTestCase {
    private func freshSuite() -> String { "test.goldengo.\(UUID().uuidString)" }

    func test_total_roundTrips() {
        let s = SharedSummary(suiteName: freshSuite())
        s.writeTodayTotal("L 1,234")
        XCTAssertEqual(s.read().todayTotalText, "L 1,234")
    }

    func test_reveal_defaultsFalse_andRoundTrips() {
        let s = SharedSummary(suiteName: freshSuite())
        XCTAssertFalse(s.read().revealOnLockScreen)       // private by default
        s.setRevealOnLockScreen(true)
        XCTAssertTrue(s.read().revealOnLockScreen)
    }

    func test_writingTotal_doesNotResetReveal() {
        let s = SharedSummary(suiteName: freshSuite())
        s.setRevealOnLockScreen(true)
        s.writeTodayTotal("L 99")                          // logging must not clobber the pref
        XCTAssertTrue(s.read().revealOnLockScreen)
    }
}
