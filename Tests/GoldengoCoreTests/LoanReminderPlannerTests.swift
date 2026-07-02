import XCTest
import GoldengoCore

final class LoanReminderPlannerTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func test_plan_firesThirtyDaysAfterNewestEvent_reArmedByCaller() {
        // WHY: the nudge exists because a lent debt silently forgotten is this feature's
        // failure mode — and any new event (more lent, partial payback) restarts the clock.
        let loan = LoanReminderPlanner.LoanInput(id: "l1", personName: "Andi",
                                                 remainingText: "ALL 5,000",
                                                 lastEventDate: day(2026, 6, 1))
        let reqs = LoanReminderPlanner.plan([loan], enabled: true, now: day(2026, 7, 2), calendar: cal)
        XCTAssertEqual(reqs.count, 1)
        XCTAssertEqual(reqs.first?.id, "l1")
        XCTAssertEqual(reqs.first?.fireDate, day(2026, 7, 1))
        XCTAssertTrue(reqs.first?.title.contains("Andi") ?? false)
        XCTAssertTrue(reqs.first?.body.contains("ALL 5,000") ?? false)
    }

    func test_plan_freshLoan_schedulesFutureNudge() {
        // A 5-day-old loan pre-schedules its day-30 nudge — no polling needed later.
        let loan = LoanReminderPlanner.LoanInput(id: "l2", personName: "Era",
                                                 remainingText: "€ 50.00",
                                                 lastEventDate: day(2026, 6, 27))
        let reqs = LoanReminderPlanner.plan([loan], enabled: true, now: day(2026, 7, 2), calendar: cal)
        XCTAssertEqual(reqs.first?.fireDate, day(2026, 7, 27))
    }

    func test_plan_disabled_returnsEmpty_soSyncClearsStaleNudges() {
        let loan = LoanReminderPlanner.LoanInput(id: "l1", personName: "Andi",
                                                 remainingText: "ALL 5,000",
                                                 lastEventDate: day(2026, 1, 1))
        XCTAssertTrue(LoanReminderPlanner.plan([loan], enabled: false,
                                               now: day(2026, 7, 2), calendar: cal).isEmpty)
    }
}
