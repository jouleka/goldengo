import XCTest
import GoldengoCore
@testable import GoldengoData
@testable import GoldengoFeatures

/// `dayGroups(from:now:calendar:)` is the orientation payload for the Home "Recent" list: it must
/// chunk the (already newest-first) rows into calendar days, newest day first, and label the two
/// most recent days relatively ("Today"/"Yesterday") so the user always knows *when* they're looking.
/// These tests lock that contract independently of SwiftUI.
final class RecentDayGroupingTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC")!,
                                      year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func snap(_ key: String, date: Date) -> ExpenseSnapshot {
        ExpenseSnapshot(dedupeKey: key, amount: 100, currencyCode: "ALL", source: .manual,
                        categoryName: "Coffee", date: date, merchantName: nil, note: nil,
                        kind: .expense, subscriptionName: nil)
    }

    /// now = 2026-06-26 10:00 UTC.
    private var now: Date { at(2026, 6, 26, 10, 0) }

    func test_groupsAreNewestDayFirst_andRowsWithinADayKeepInputOrder() {
        // Input is already newest-first (Home fetch guarantees this). Two rows today (later then
        // earlier), one yesterday.
        let rows = [
            snap("today-late", date: at(2026, 6, 26, 9, 0)),
            snap("today-early", date: at(2026, 6, 26, 7, 0)),
            snap("yesterday", date: at(2026, 6, 25, 20, 0)),
        ]
        let groups = RecentExpensesModel.dayGroups(from: rows, now: now, calendar: cal)

        XCTAssertEqual(groups.map(\.title), ["Today", "Yesterday"], "Newest day must come first")
        XCTAssertEqual(groups[0].rows.map(\.dedupeKey), ["today-late", "today-early"],
                       "Rows within a day must keep newest-first input order")
        XCTAssertEqual(groups[1].rows.map(\.dedupeKey), ["yesterday"])
    }

    func test_rowsMinutesApartButAcrossMidnightLandInDifferentDays() {
        // 00:01 today and 23:59 yesterday are two minutes apart but two calendar days — they must
        // NOT collapse into one group.
        let rows = [
            snap("after-midnight", date: at(2026, 6, 26, 0, 1)),
            snap("before-midnight", date: at(2026, 6, 25, 23, 59)),
        ]
        let groups = RecentExpensesModel.dayGroups(from: rows, now: now, calendar: cal)

        XCTAssertEqual(groups.count, 2, "A two-minute gap across midnight is two days")
        XCTAssertEqual(groups[0].rows.map(\.dedupeKey), ["after-midnight"])
        XCTAssertEqual(groups[1].rows.map(\.dedupeKey), ["before-midnight"])
    }

    func test_labels_todayYesterdayAreRelative_olderIsAConcreteDate() {
        let rows = [
            snap("t", date: at(2026, 6, 26, 9, 0)),
            snap("y", date: at(2026, 6, 25, 9, 0)),
            snap("old", date: at(2026, 6, 23, 9, 0)),
        ]
        let groups = RecentExpensesModel.dayGroups(from: rows, now: now, calendar: cal)

        XCTAssertEqual(groups[0].title, "Today")
        XCTAssertEqual(groups[1].title, "Yesterday")
        // The older day must read as a concrete date, never a stale relative word.
        XCTAssertNotEqual(groups[2].title, "Today")
        XCTAssertNotEqual(groups[2].title, "Yesterday")
        XCTAssertFalse(groups[2].title.isEmpty)
    }

    func test_emptyInputProducesNoGroups() {
        XCTAssertEqual(RecentExpensesModel.dayGroups(from: [], now: now, calendar: cal).count, 0)
    }

    // MARK: monthGroups — the Year view buckets by calendar month

    func test_monthGroups_newestMonthFirst_withRelativeAndYearedLabels() {
        // now = June 2026. Rows across this month, an earlier month this year, and a prior year.
        let rows = [
            snap("jun", date: at(2026, 6, 20, 9, 0)),
            snap("may", date: at(2026, 5, 4, 9, 0)),
            snap("dec25", date: at(2025, 12, 31, 9, 0)),
        ]
        let groups = RecentExpensesModel.monthGroups(from: rows, now: now, calendar: cal)

        XCTAssertEqual(groups.map(\.title), ["This month", "May", "December 2025"],
                       "current month is relative; same-year months drop the year; prior years keep it")
        XCTAssertEqual(groups.map { $0.rows.map(\.dedupeKey) }, [["jun"], ["may"], ["dec25"]],
                       "newest month first, each row in its month")
    }

    func test_monthGroups_bucketsMultipleRowsOfAMonthTogether() {
        let rows = [
            snap("jun-late", date: at(2026, 6, 20, 9, 0)),
            snap("jun-early", date: at(2026, 6, 2, 9, 0)),
        ]
        let groups = RecentExpensesModel.monthGroups(from: rows, now: now, calendar: cal)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].rows.map(\.dedupeKey), ["jun-late", "jun-early"])
    }
}
