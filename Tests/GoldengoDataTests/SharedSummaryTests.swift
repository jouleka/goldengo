import XCTest
@testable import GoldengoData

final class SharedSummaryTests: XCTestCase {
    func test_roundTrip_usesStandardDefaultsWhenNoAppGroup() {
        let s = SharedSummary(suiteName: nil)   // falls back to .standard in tests
        s.write(todayTotalText: "L 1,234", redacted: false)
        XCTAssertEqual(s.read().todayTotalText, "L 1,234")
        XCTAssertEqual(s.read().redacted, false)
    }
}
