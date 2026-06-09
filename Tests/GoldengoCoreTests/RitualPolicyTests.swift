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
    func test_eveningWrapAround_oneAM_isEvening() {
        // 01:00 — past midnight is still "evening" (18:00..04:00). reflectedDate is the prior evening,
        // so on this new calendar day it is NOT reflected-today → .evening.
        let r = RitualPolicy.prompt(now: at(1), intentionDate: nil, reflectedDate: at(22, day: 8), calendar: cal)
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
}
