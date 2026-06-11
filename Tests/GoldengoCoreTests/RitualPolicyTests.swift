import XCTest
@testable import GoldengoCore

final class RitualPolicyTests: XCTestCase {
    // A fixed UTC calendar so component(.hour) is deterministic regardless of the test host's zone.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    // Build a Date at a given UTC hour on a fixed day (2026-06-09).
    private func at(_ hour: Int, day: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: 30))!
    }

    func test_clampNudges_pinToTheirWindows() {
        XCTAssertEqual(RitualPolicy.clampMorningNudge(minutes: 480), 480)    // 08:00 passes through
        XCTAssertEqual(RitualPolicy.clampMorningNudge(minutes: 0), 300)     // below → 05:00
        XCTAssertEqual(RitualPolicy.clampMorningNudge(minutes: 900), 705)   // above → 11:45
        XCTAssertEqual(RitualPolicy.clampEveningNudge(minutes: 1260), 1260) // 21:00 passes through
        XCTAssertEqual(RitualPolicy.clampEveningNudge(minutes: 600), 1080)  // below → 18:00
        XCTAssertEqual(RitualPolicy.clampEveningNudge(minutes: 1440), 1425) // above → 23:45
        // The shipped defaults must already be inside the windows (no first-run clamping).
        XCTAssertEqual(RitualPolicy.clampMorningNudge(minutes: RitualPolicy.defaultMorningNudgeMinutes),
                       RitualPolicy.defaultMorningNudgeMinutes)
        XCTAssertEqual(RitualPolicy.clampEveningNudge(minutes: RitualPolicy.defaultEveningNudgeMinutes),
                       RitualPolicy.defaultEveningNudgeMinutes)
    }

    func test_skippedToday_suppressesMorning_forTheRestOfTheDay() {
        // GOL-97: Skip must mean skip — at most one morning prompt per day, ever.
        let r = RitualPolicy.prompt(now: at(9), intentionDate: nil, reflectedDate: nil,
                                    skippedDate: at(7), calendar: cal)
        XCTAssertEqual(r, .none)
    }

    func test_skippedYesterday_morningPromptsAgainToday() {
        let r = RitualPolicy.prompt(now: at(8), intentionDate: nil, reflectedDate: nil,
                                    skippedDate: at(8, day: 8), calendar: cal)
        XCTAssertEqual(r, .morning, "A skip is for the day, not forever")
    }

    func test_skippedThisMorning_doesNotSuppressTheEvening() {
        let r = RitualPolicy.prompt(now: at(20), intentionDate: nil, reflectedDate: nil,
                                    skippedDate: at(7), calendar: cal)
        XCTAssertEqual(r, .evening)
    }

    func test_morningWindow_noIntentionToday_returnsMorning() {
        let r = RitualPolicy.prompt(now: at(8), intentionDate: nil, reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .morning)
    }
    func test_morningWindow_intentionAlreadySetToday_notMorning() {
        let now = at(8)
        let r = RitualPolicy.prompt(now: now, intentionDate: at(6), reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .none)
    }
    func test_intentionSetYesterday_morningAgainToday() {
        let r = RitualPolicy.prompt(now: at(8), intentionDate: at(8, day: 8), reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .morning)
    }
    func test_eveningWindow_notReflected_returnsEvening() {
        let r = RitualPolicy.prompt(now: at(21), intentionDate: at(8), reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .evening)
    }
    func test_eveningWindow_reflectedToday_returnsNone() {
        let now = at(21)
        let r = RitualPolicy.prompt(now: now, intentionDate: at(8), reflectedDate: at(20), calendar: cal)
        XCTAssertEqual(r, .none)
    }
    func test_eveningWrapAround_oneAM_notReflected_isEvening() {
        // 01:00 is inside the evening window (18:00..04:00, wraps midnight); nothing reflected
        // this session → .evening. (Pure window-membership: reflectedDate nil.)
        let r = RitualPolicy.prompt(now: at(1), intentionDate: nil, reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .evening)
    }
    func test_evening_suppressed_postMidnight_sameSession() {
        // Reflected at 23:00 day 9, re-opened at 01:00 day 10 the SAME continuous night → the
        // reflection is within this evening session (started 18:00 day 9) → suppressed → .none.
        // (Regression guard for the calendar-day-vs-session boundary bug.)
        let r = RitualPolicy.prompt(now: at(1, day: 10), intentionDate: nil,
                                    reflectedDate: at(23, day: 9), calendar: cal)
        XCTAssertEqual(r, .none)
    }
    func test_evening_eligibleAgain_nextNight() {
        // Reflected last night at 20:00 (day 9); tonight at 21:00 (day 10) is a NEW session → .evening.
        let r = RitualPolicy.prompt(now: at(21, day: 10), intentionDate: nil,
                                    reflectedDate: at(20, day: 9), calendar: cal)
        XCTAssertEqual(r, .evening)
    }
    func test_midday_outOfBothWindows_returnsNone() {
        let r = RitualPolicy.prompt(now: at(14), intentionDate: nil, reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .none)
    }
    func test_boundary_hour12_isNotMorning() {     // morningHours == 5..<12, so 12 is excluded
        let r = RitualPolicy.prompt(now: at(12), intentionDate: nil, reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .none)
    }
    func test_boundary_hour18_isEvening() {        // eveningStartHour == 18 (inclusive)
        let r = RitualPolicy.prompt(now: at(18), intentionDate: nil, reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .evening)
    }
    func test_boundary_hour3_isEvening_hour4_isNone() {   // evening end: hour < 4, so 3 in / 4 out
        XCTAssertEqual(RitualPolicy.prompt(now: at(3), intentionDate: nil, reflectedDate: nil, calendar: cal), .evening)
        XCTAssertEqual(RitualPolicy.prompt(now: at(4), intentionDate: nil, reflectedDate: nil, calendar: cal), .none)
    }
    func test_boundary_hour5_isMorning() {               // morning start: 5..<12 (inclusive at 5)
        let r = RitualPolicy.prompt(now: at(5), intentionDate: nil, reflectedDate: nil, calendar: cal)
        XCTAssertEqual(r, .morning)
    }
}
