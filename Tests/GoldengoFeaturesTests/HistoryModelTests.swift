import XCTest
import GoldengoCore
@testable import GoldengoData
@testable import GoldengoFeatures

/// `HistoryModel` drives the period browser. The behaviors a user feels: changing the granularity
/// snaps you back to the present, you can never step into the future, and stepping back moves exactly
/// one period. Verified against a fake reader so no store is needed.
@MainActor
final class HistoryModelTests: XCTestCase {

    private func range(endingAt end: Date) -> PeriodRange { PeriodRange(start: end.addingTimeInterval(-3600), end: end) }

    func test_load_failure_setsLoadFailed() async {
        let m = HistoryModel(reader: FailingHistoryReader())
        await m.load()
        XCTAssertTrue(m.loadFailed)
        XCTAssertNil(m.snapshot)
    }

    func test_setScale_resetsAnchorToNow_andReloads() async {
        // Start anchored in the past; switching scale must jump back to the present.
        let past = Date(timeIntervalSinceNow: -400 * 24 * 3600)
        let reader = SpyHistoryReader(range: range(endingAt: .now.addingTimeInterval(-10)))
        let m = HistoryModel(reader: reader, now: past)
        await m.load()
        XCTAssertEqual(m.anchor, past)

        await m.setScale(.week)
        XCTAssertEqual(m.scale, .week)
        XCTAssertLessThan(abs(m.anchor.timeIntervalSinceNow), 2, "changing scale returns to the present")
        let lastScale = await reader.lastScale
        XCTAssertEqual(lastScale, .week)
    }

    func test_stepForward_isNoOp_whenViewingThePresentPeriod() async {
        // A range whose end is in the future == the current period: forward must be disabled.
        let reader = SpyHistoryReader(range: range(endingAt: .now.addingTimeInterval(99_999)))
        let m = HistoryModel(reader: reader)
        await m.load()
        XCTAssertFalse(m.canStepForward)
        let anchorBefore = m.anchor
        let callsBefore = await reader.callCount

        await m.stepForward()
        XCTAssertEqual(m.anchor, anchorBefore, "no movement into the future")
        let callsAfter = await reader.callCount
        XCTAssertEqual(callsAfter, callsBefore, "and no wasted reload")
    }

    func test_stepBackward_movesAnchorBackExactlyOnePeriod() async {
        let reader = SpyHistoryReader(range: range(endingAt: .now.addingTimeInterval(-10)))
        let fixedNow = Date(timeIntervalSince1970: 1_780_000_000)
        let m = HistoryModel(reader: reader, now: fixedNow)   // scale defaults to .month
        await m.load()

        await m.stepBackward()
        XCTAssertEqual(m.anchor, PeriodScale.month.anchor(fixedNow, steppedBy: -1))
        let lastAnchor = await reader.lastAnchor
        XCTAssertEqual(lastAnchor, m.anchor, "the reader is asked for the period we stepped to")
    }

    func test_appear_landsOnCurrentPeriod_keepingChosenScale() async {
        // Opening History should always show the present (no stale launch-time anchor), but keep the
        // granularity the user last chose.
        let reader = SpyHistoryReader(range: range(endingAt: .now.addingTimeInterval(-10)))
        let past = Date(timeIntervalSinceNow: -300 * 24 * 3600)
        let m = HistoryModel(reader: reader, now: past)
        await m.setScale(.year)
        await m.stepBackward()                       // wander into a past year
        let wandered = m.anchor

        await m.appear()
        XCTAssertEqual(m.scale, .year, "appear preserves the chosen scale")
        XCTAssertLessThan(abs(m.anchor.timeIntervalSinceNow), 2, "appear lands on the current period")
        XCTAssertNotEqual(m.anchor, wandered)
    }

    func test_stepForward_movesForward_whenViewingAPastPeriod() async {
        let reader = SpyHistoryReader(range: range(endingAt: .now.addingTimeInterval(-10)))  // already elapsed
        let fixedNow = Date(timeIntervalSince1970: 1_780_000_000)
        let m = HistoryModel(reader: reader, now: fixedNow)
        await m.load()
        XCTAssertTrue(m.canStepForward)

        await m.stepForward()
        XCTAssertEqual(m.anchor, PeriodScale.month.anchor(fixedNow, steppedBy: 1))
    }
}

/// Records what it was asked for; returns a fixed-range snapshot so `canStepForward` is controllable.
private actor SpyHistoryReader: HistoryReading {
    private(set) var lastScale: PeriodScale?
    private(set) var lastAnchor: Date?
    private(set) var callCount = 0
    private let fixedRange: PeriodRange
    init(range: PeriodRange) { self.fixedRange = range }

    func historyData(scale: PeriodScale, anchor: Date, displayCurrency: CurrencyCode,
                     rates: RateTable, now: Date, calendar: Calendar) async throws -> HistorySnapshot {
        callCount += 1; lastScale = scale; lastAnchor = anchor
        return HistorySnapshot(scale: scale, range: fixedRange, totalSpent: 0, expenseCount: 0,
                               rows: [], ratesAsOf: nil)
    }
    func deleteExpense(dedupeKey: String) async throws {}
    func restoreExpense(dedupeKey: String) async throws {}
    func updateExpense(dedupeKey: String, amount: Decimal, currency: CurrencyCode?, merchant: String?,
                       note: String?, categoryName: String?, date: Date, fundedBySourceID: String?) async throws {}
}

private struct FailingHistoryReader: HistoryReading {
    struct Boom: Error {}
    func historyData(scale: PeriodScale, anchor: Date, displayCurrency: CurrencyCode,
                     rates: RateTable, now: Date, calendar: Calendar) async throws -> HistorySnapshot { throw Boom() }
    func deleteExpense(dedupeKey: String) async throws { throw Boom() }
    func restoreExpense(dedupeKey: String) async throws { throw Boom() }
    func updateExpense(dedupeKey: String, amount: Decimal, currency: CurrencyCode?, merchant: String?,
                       note: String?, categoryName: String?, date: Date, fundedBySourceID: String?) async throws { throw Boom() }
}
