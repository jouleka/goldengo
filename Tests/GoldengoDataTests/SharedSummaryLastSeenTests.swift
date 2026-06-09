import XCTest
@testable import GoldengoData

final class SharedSummaryLastSeenTests: XCTestCase {
    func test_lastSeen_roundTrips() {
        let s = SharedSummary(suiteName: "reentry-test-\(UUID().uuidString)")
        XCTAssertNil(s.readLastSeen())
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        s.setLastSeen(d)
        XCTAssertEqual(s.readLastSeen(), d)
    }
}
