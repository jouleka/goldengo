import XCTest
import GoldengoCore

final class LoanReminderPlannerTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func test_plan_schedulesNextThreeMonthlyNudges_freshLoan() {
        // WHY three: ignoring a nudge must never end the nudging — the next ones are already
        // queued even if the app isn't opened again for months.
        let loan = LoanReminderPlanner.LoanInput(id: "l1", personName: "Andi",
                                                 remainingText: "ALL 5,000",
                                                 lastEventDate: day(2026, 6, 27))
        let reqs = LoanReminderPlanner.plan([loan], enabled: true, now: day(2026, 7, 2), calendar: cal)
        XCTAssertEqual(reqs.map(\.fireDate), [day(2026, 7, 27), day(2026, 8, 26), day(2026, 9, 25)])
        // Distinct ids per occurrence — the scheduler keys identifiers on them.
        XCTAssertEqual(reqs.map(\.id), ["l1#1", "l1#2", "l1#3"])
        XCTAssertTrue(reqs.first?.title.contains("Andi") ?? false)
        XCTAssertTrue(reqs.first?.body.contains("ALL 5,000") ?? false)
    }

    func test_plan_pastNudgesRollForward_neverSchedulesThePast() {
        // WHY: a fired nudge is gone — re-syncing must queue the NEXT grid dates, not
        // resurrect day-30 after it already showed.
        let loan = LoanReminderPlanner.LoanInput(id: "l1", personName: "Andi",
                                                 remainingText: "ALL 5,000",
                                                 lastEventDate: day(2026, 6, 1))
        let reqs = LoanReminderPlanner.plan([loan], enabled: true, now: day(2026, 7, 2), calendar: cal)
        XCTAssertEqual(reqs.map(\.fireDate), [day(2026, 7, 31), day(2026, 8, 30), day(2026, 9, 29)])
        XCTAssertEqual(reqs.map(\.id), ["l1#2", "l1#3", "l1#4"])
    }

    func test_nextNudge_matchesTheFirstScheduledFireDate() {
        // WHY: the date shown on the claim card must be exactly the date the notification
        // actually fires — a displayed promise that differs from the schedule is a lie.
        XCTAssertEqual(LoanReminderPlanner.nextNudge(after: day(2026, 6, 27), now: day(2026, 7, 2), calendar: cal),
                       day(2026, 7, 27))
        XCTAssertEqual(LoanReminderPlanner.nextNudge(after: day(2026, 6, 1), now: day(2026, 7, 2), calendar: cal),
                       day(2026, 7, 31))
    }

    func test_plan_disabled_returnsEmpty_soSyncClearsStaleNudges() {
        let loan = LoanReminderPlanner.LoanInput(id: "l1", personName: "Andi",
                                                 remainingText: "ALL 5,000",
                                                 lastEventDate: day(2026, 1, 1))
        XCTAssertTrue(LoanReminderPlanner.plan([loan], enabled: false,
                                               now: day(2026, 7, 2), calendar: cal).isEmpty)
    }
}
