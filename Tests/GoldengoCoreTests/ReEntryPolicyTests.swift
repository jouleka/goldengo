import XCTest
@testable import GoldengoCore

final class ReEntryPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private func ago(_ days: Int) -> Date { now.addingTimeInterval(Double(-days) * 86_400) }

    func test_daysAway_countsWholeDays() {
        XCTAssertEqual(ReEntryPolicy.daysAway(lastSeen: ago(4), now: now), 4)
        XCTAssertEqual(ReEntryPolicy.daysAway(lastSeen: ago(10), now: now), 10)
    }
    func test_daysAway_nilWhenNoLastSeen() {
        XCTAssertNil(ReEntryPolicy.daysAway(lastSeen: nil, now: now))
    }
    func test_daysAway_nilSameDayOrFuture() {
        XCTAssertNil(ReEntryPolicy.daysAway(lastSeen: now.addingTimeInterval(-3600), now: now))
        XCTAssertNil(ReEntryPolicy.daysAway(lastSeen: now.addingTimeInterval(86_400), now: now))
    }
    func test_shouldShow_thresholdBoundary() {
        XCTAssertFalse(ReEntryPolicy.shouldShow(lastSeen: ago(3), now: now))
        XCTAssertTrue(ReEntryPolicy.shouldShow(lastSeen: ago(4), now: now))
        XCTAssertFalse(ReEntryPolicy.shouldShow(lastSeen: nil, now: now))
    }
}
