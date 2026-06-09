import XCTest
@testable import GoldengoData

final class SharedSummaryRitualTests: XCTestCase {
    private func freshSummary() -> SharedSummary { SharedSummary(suiteName: "ritual-test-\(UUID().uuidString)") }

    func test_ritualEnabled_defaultsFalse_andRoundTrips() {
        let s = freshSummary()
        XCTAssertFalse(s.ritualEnabled())
        s.setRitualEnabled(true)
        XCTAssertTrue(s.ritualEnabled())
    }
    func test_intention_roundTripsTextAndDate() {
        let s = freshSummary()
        XCTAssertNil(s.readIntention())
        let d = Date(timeIntervalSince1970: 1_780_000_000)
        s.setIntention("be present", on: d)
        let read = s.readIntention()
        XCTAssertEqual(read?.text, "be present")
        XCTAssertEqual(read?.date, d)
        XCTAssertEqual(s.readIntentionDate(), d)
    }
    func test_reflected_roundTrips_nilWhenUnset() {
        let s = freshSummary()
        XCTAssertNil(s.readReflectedDate())
        let d = Date(timeIntervalSince1970: 1_780_050_000)
        s.setReflected(on: d)
        XCTAssertEqual(s.readReflectedDate(), d)
    }
}
