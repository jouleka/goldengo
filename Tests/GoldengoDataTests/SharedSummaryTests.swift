import XCTest
@testable import GoldengoData
import GoldengoCore

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

    // F5 — pendingTab round-trip
    func test_pendingTab_roundTrip() {
        let s = SharedSummary(suiteName: freshSuite())
        XCTAssertNil(s.readPendingTab())                   // absent by default
        s.setPendingTab(0)
        XCTAssertEqual(s.readPendingTab(), 0)              // set to 0 → read 0
        s.setPendingTab(nil)
        XCTAssertNil(s.readPendingTab())                   // cleared → nil
    }

    func test_preferredCurrency_defaultsToLek_whenUnset() {
        let s = SharedSummary(suiteName: freshSuite())
        XCTAssertEqual(s.readPreferredCurrency(), .all)
    }

    func test_preferredCurrency_roundTrips() {
        let s = SharedSummary(suiteName: freshSuite())
        s.setPreferredCurrency(.eur)
        XCTAssertEqual(s.readPreferredCurrency(), .eur)
    }

    func test_preferredCurrency_persistsAcrossInstances_onSameSuite() {
        let suite = freshSuite()
        SharedSummary(suiteName: suite).setPreferredCurrency(CurrencyCode("USD"))
        XCTAssertEqual(SharedSummary(suiteName: suite).readPreferredCurrency(), CurrencyCode("USD"))
    }
}
