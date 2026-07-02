import XCTest
@testable import GoldengoCore

/// `PeriodScale` is the History browser's reliability core: it decides which expenses belong to the
/// period on screen and whether the user may step forward. A silent off-by-one here misfiles a whole
/// month, so the boundaries, week-start locale, stepping arithmetic, future-guard, and relative labels
/// are all pinned here.
final class PeriodScaleTests: XCTestCase {

    private func cal(firstWeekday: Int = 2, tz: String = "UTC") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        c.firstWeekday = firstWeekday   // 2 = Monday
        return c
    }

    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0, tz: String = "UTC") -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        c.timeZone = TimeZone(identifier: tz)!
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: range(containing:)

    func test_dayRange_isStartOfDayToNextStartOfDay() {
        let r = PeriodScale.day.range(containing: at(2026, 6, 26, 14, 30), calendar: cal())
        XCTAssertEqual(r.start, at(2026, 6, 26, 0, 0))
        XCTAssertEqual(r.end, at(2026, 6, 27, 0, 0))
    }

    func test_monthRange_spansTheCalendarMonth() {
        let r = PeriodScale.month.range(containing: at(2026, 6, 26), calendar: cal())
        XCTAssertEqual(r.start, at(2026, 6, 1, 0, 0))
        XCTAssertEqual(r.end, at(2026, 7, 1, 0, 0))
    }

    func test_yearRange_spansTheCalendarYear() {
        let r = PeriodScale.year.range(containing: at(2026, 6, 26), calendar: cal())
        XCTAssertEqual(r.start, at(2026, 1, 1, 0, 0))
        XCTAssertEqual(r.end, at(2027, 1, 1, 0, 0))
    }

    func test_weekRange_startsOnLocaleFirstWeekday_andSpansSevenDays() {
        let date = at(2026, 6, 26)  // a Friday
        let r = PeriodScale.week.range(containing: date, calendar: cal(firstWeekday: 2))
        XCTAssertTrue(r.contains(date))
        XCTAssertEqual(cal().component(.weekday, from: r.start), 2, "Week must start on the first weekday (Mon)")
        XCTAssertEqual(r.end.timeIntervalSince(r.start), 7 * 24 * 3600, accuracy: 1)
    }

    func test_weekRange_respectsADifferentFirstWeekday() {
        let r = PeriodScale.week.range(containing: at(2026, 6, 26), calendar: cal(firstWeekday: 1))
        XCTAssertEqual(cal().component(.weekday, from: r.start), 1, "Sunday-start locale must start the week on Sunday")
    }

    func test_monthRange_handlesLeapFebruary() {
        let r = PeriodScale.month.range(containing: at(2024, 2, 15), calendar: cal())
        XCTAssertEqual(r.end, at(2024, 3, 1, 0, 0))
        XCTAssertTrue(r.contains(at(2024, 2, 29, 23, 0)), "Feb 29 must fall inside a leap February")
    }

    func test_dayRange_acrossDSTSpringForward_isOneLocalDay() {
        // 2026-03-08 is the US spring-forward (a 23-hour local day). The range must still be exactly
        // local-midnight to next local-midnight, and contain local noon.
        let tz = "America/New_York"
        let r = PeriodScale.day.range(containing: at(2026, 3, 8, 12, 0, tz: tz), calendar: cal(tz: tz))
        XCTAssertEqual(r.start, at(2026, 3, 8, 0, 0, tz: tz))
        XCTAssertEqual(r.end, at(2026, 3, 9, 0, 0, tz: tz))
        XCTAssertTrue(r.contains(at(2026, 3, 8, 12, 0, tz: tz)))
    }

    // MARK: contains — half-open [start, end)

    func test_contains_startInclusive_endExclusive() {
        let r = PeriodScale.month.range(containing: at(2026, 6, 10), calendar: cal())
        XCTAssertTrue(r.contains(r.start), "start is inclusive")
        XCTAssertFalse(r.contains(r.end), "end is exclusive — the first instant of next month belongs to next month")
    }

    // MARK: anchor(steppedBy:)

    func test_monthStep_crossesYearBoundary() {
        let prev = PeriodScale.month.anchor(at(2026, 1, 15), steppedBy: -1, calendar: cal())
        let r = PeriodScale.month.range(containing: prev, calendar: cal())
        XCTAssertEqual(r.start, at(2025, 12, 1, 0, 0))
    }

    func test_yearStep_movesWholeYears() {
        let back = PeriodScale.year.anchor(at(2026, 3, 1), steppedBy: -2, calendar: cal())
        XCTAssertEqual(PeriodScale.year.range(containing: back, calendar: cal()).start, at(2024, 1, 1, 0, 0))
    }

    func test_dayAndWeekStep() {
        XCTAssertEqual(PeriodScale.day.range(containing:
            PeriodScale.day.anchor(at(2026, 6, 26), steppedBy: -1, calendar: cal()), calendar: cal()).start,
            at(2026, 6, 25, 0, 0))
        let weekBack = PeriodScale.week.anchor(at(2026, 6, 26), steppedBy: -1, calendar: cal())
        XCTAssertEqual(weekBack, at(2026, 6, 19), "one week back is exactly seven days")
    }

    // MARK: future-guard

    func test_hasFullyElapsed_falseForCurrentPeriod_trueForPast() {
        let now = at(2026, 6, 26, 12, 0)
        let current = PeriodScale.month.range(containing: now, calendar: cal())
        XCTAssertFalse(current.hasFullyElapsed(by: now), "the period containing now hasn't ended — no stepping into the future")
        let past = PeriodScale.month.range(containing: at(2026, 5, 15), calendar: cal())
        XCTAssertTrue(past.hasFullyElapsed(by: now), "last month has ended — forward is allowed")
    }

    // MARK: labels

    private let en = Locale(identifier: "en_US")

    func test_dayLabels_areRelative() {
        let now = at(2026, 6, 26, 9, 0)
        XCTAssertEqual(PeriodScale.day.label(for: .init(start: at(2026, 6, 26, 0, 0), end: at(2026, 6, 27, 0, 0)),
                                             now: now, calendar: cal(), locale: en), "Today")
        XCTAssertEqual(PeriodScale.day.label(for: .init(start: at(2026, 6, 25, 0, 0), end: at(2026, 6, 26, 0, 0)),
                                             now: now, calendar: cal(), locale: en), "Yesterday")
        let older = PeriodScale.day.label(for: .init(start: at(2026, 6, 20, 0, 0), end: at(2026, 6, 21, 0, 0)),
                                          now: now, calendar: cal(), locale: en)
        XCTAssertNotEqual(older, "Today"); XCTAssertNotEqual(older, "Yesterday"); XCTAssertFalse(older.isEmpty)
    }

    func test_monthAndYearLabels() {
        let now = at(2026, 6, 26)
        let month = PeriodScale.month.label(for: PeriodScale.month.range(containing: at(2026, 6, 1), calendar: cal()),
                                            now: now, calendar: cal(), locale: en)
        XCTAssertTrue(month.contains("June"), "month label names the month — got \(month)")
        XCTAssertTrue(month.contains("2026"), "month label carries the year — got \(month)")
        XCTAssertEqual(PeriodScale.year.label(for: PeriodScale.year.range(containing: at(2026, 6, 1), calendar: cal()),
                                              now: now, calendar: cal(), locale: en), "2026")
    }

    func test_weekLabel_currentWeekIsRelative() {
        let now = at(2026, 6, 26, 9, 0)
        let thisWeek = PeriodScale.week.range(containing: now, calendar: cal())
        XCTAssertEqual(PeriodScale.week.label(for: thisWeek, now: now, calendar: cal(), locale: en), "This week")
    }

    func test_dayLabel_priorYearCarriesTheYear() {
        // Stepping back into last year must not render a label identical to this year's same day.
        let now = at(2026, 6, 26, 9, 0)
        let label = PeriodScale.day.label(for: .init(start: at(2025, 1, 5, 0, 0), end: at(2025, 1, 6, 0, 0)),
                                          now: now, calendar: cal(), locale: en)
        XCTAssertTrue(label.contains("2025"), "a prior-year day must carry its year — got \(label)")
    }

    func test_weekLabel_priorYearCarriesTheYear() {
        let now = at(2026, 6, 26, 9, 0)
        let pastWeek = PeriodScale.week.range(containing: at(2024, 6, 12), calendar: cal())
        let label = PeriodScale.week.label(for: pastWeek, now: now, calendar: cal(), locale: en)
        XCTAssertTrue(label.contains("2024"), "a prior-year week must carry its year — got \(label)")
    }

    func test_weekLabel_straddlingTheYearBoundaryShowsBothYears() {
        // The week containing 2025-12-31 spans Dec 2025 → Jan 2026; both years must be visible.
        let now = at(2026, 6, 26, 9, 0)
        let straddle = PeriodScale.week.range(containing: at(2025, 12, 31), calendar: cal())
        let label = PeriodScale.week.label(for: straddle, now: now, calendar: cal(), locale: en)
        XCTAssertTrue(label.contains("2025") && label.contains("2026"),
                      "a Dec/Jan week must show both years — got \(label)")
    }
}
