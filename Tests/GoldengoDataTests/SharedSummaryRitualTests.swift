import XCTest
import GoldengoCore
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

    func test_nudgeMinutes_roundTrip_andWindowDefaults() {
        let s = freshSummary()
        XCTAssertEqual(s.ritualMorningMinutes(), RitualPolicy.defaultMorningNudgeMinutes,
                       "Unset reads as the shipped 08:00 default")
        XCTAssertEqual(s.ritualEveningMinutes(), RitualPolicy.defaultEveningNudgeMinutes)
        s.setRitualMorningMinutes(6 * 60 + 30)
        s.setRitualEveningMinutes(22 * 60)
        XCTAssertEqual(s.ritualMorningMinutes(), 390)
        XCTAssertEqual(s.ritualEveningMinutes(), 1320)
    }

    func test_intentionHistory_roundTrip_andCorruptDataYieldsEmpty() {
        let suite = "ritual-test-\(UUID().uuidString)"
        let s = SharedSummary(suiteName: suite)
        XCTAssertEqual(s.readIntentionHistory(), [])
        let entries = [IntentionEntry(date: Date(timeIntervalSinceReferenceDate: 0), text: "begin")]
        s.setIntentionHistory(entries)
        XCTAssertEqual(s.readIntentionHistory(), entries)
        // Corrupt the blob through a parallel handle on the same suite.
        UserDefaults(suiteName: suite)!.set(Data("not json".utf8), forKey: SharedSummary.ritualIntentionHistoryKey)
        XCTAssertEqual(s.readIntentionHistory(), [], "Corrupt blob restarts the journal, never crashes")
    }

    func test_setIntention_journalsAutomatically_sameDayReplaces() {
        let s = freshSummary()
        s.setIntention("draft", on: Date(timeIntervalSinceReferenceDate: 1_000))
        s.setIntention("final", on: Date(timeIntervalSinceReferenceDate: 2_000))   // same day
        XCTAssertEqual(s.readIntentionHistory().map(\.text), ["final"],
                       "Saving twice in one morning keeps one journal entry")
    }
}
