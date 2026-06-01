import XCTest
@testable import GoldengoCore

final class SubscriptionReminderPlannerTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
    private func input(_ id: String, _ next: Date) -> SubscriptionReminderPlanner.ReminderInput {
        .init(id: id, title: "T", body: "B", nextCharge: next)
    }

    func test_firesLeadDaysBeforeNextCharge() {
        let out = SubscriptionReminderPlanner.plan([input("x", day(2026, 4, 5))],
                                                   leadDays: 1, now: day(2026, 3, 1), calendar: cal)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: out[0].fireDate),
                       cal.dateComponents([.year, .month, .day], from: day(2026, 4, 4)))
        XCTAssertEqual(out[0].id, "x")
    }

    func test_skipsRemindersWhoseFireDateIsPast() {
        let out = SubscriptionReminderPlanner.plan([input("x", day(2026, 1, 1))],
                                                   leadDays: 1, now: day(2026, 3, 1), calendar: cal)
        XCTAssertTrue(out.isEmpty)   // fire date Dec 31 is before now
    }

    func test_leadZeroFiresOnChargeDay() {
        let out = SubscriptionReminderPlanner.plan([input("x", day(2026, 4, 5))],
                                                   leadDays: 0, now: day(2026, 3, 1), calendar: cal)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: out[0].fireDate),
                       cal.dateComponents([.year, .month, .day], from: day(2026, 4, 5)))
    }

    func test_multipleInputs_preservedAndFiltered() {
        let out = SubscriptionReminderPlanner.plan(
            [input("future", day(2026, 5, 10)), input("past", day(2026, 1, 1))],
            leadDays: 2, now: day(2026, 3, 1), calendar: cal)
        XCTAssertEqual(out.map(\.id), ["future"])
    }

    func test_empty() {
        XCTAssertTrue(SubscriptionReminderPlanner.plan([], leadDays: 1, now: day(2026, 3, 1), calendar: cal).isEmpty)
    }
}
