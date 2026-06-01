import XCTest
@testable import GoldengoCore

final class SubscriptionDetectorTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func occ(_ id: String, _ date: Date, _ amount: Double, _ merchant: String, _ cur: CurrencyCode = .all) -> TransactionOccurrence {
        TransactionOccurrence(id: id, date: date, amount: Decimal(amount), currency: cur, merchant: merchant)
    }

    func test_detectsMonthlySubscription_threeOccurrences() {
        let occs = [
            occ("1", day(2026, 1, 5), 9.99, "Netflix"),
            occ("2", day(2026, 2, 5), 9.99, "NETFLIX 4471"),   // numeric token dropped by normalizer
            occ("3", day(2026, 3, 5), 9.99, "Netflix"),
        ]
        let result = SubscriptionDetector.detect(occs, options: .init(now: day(2026, 3, 10)))
        XCTAssertEqual(result.count, 1)
        let c = result[0]
        XCTAssertEqual(c.cadence, .monthly)
        XCTAssertEqual(c.occurrenceCount, 3)
        XCTAssertEqual(c.amount, Decimal(9.99))
        XCTAssertEqual(c.normalizedMerchant, "NETFLIX")
        XCTAssertFalse(c.isVariableAmount)
        XCTAssertFalse(c.hadTrial)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: c.predictedNextCharge),
                       cal.dateComponents([.year, .month, .day], from: day(2026, 4, 5)))
        XCTAssertGreaterThan(c.confidence, 0.7)
    }

    func test_twoMonthlyChargesAreNotEnough() {
        let occs = [occ("1", day(2026, 1, 5), 9.99, "Spotify"),
                    occ("2", day(2026, 2, 5), 9.99, "Spotify")]
        XCTAssertTrue(SubscriptionDetector.detect(occs, options: .init(now: day(2026, 2, 10))).isEmpty)
    }

    func test_detectsYearlyWithTwoOccurrences() {
        let occs = [occ("1", day(2024, 6, 1), 99.0, "iCloud+"),
                    occ("2", day(2025, 6, 2), 99.0, "iCloud+")]
        let result = SubscriptionDetector.detect(occs, options: .init(now: day(2025, 7, 1)))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].cadence, .yearly)
        XCTAssertEqual(result[0].occurrenceCount, 2)
    }

    func test_detectsWeeklyAndPredictsForward_pastLastCharge() {
        let base = day(2026, 1, 1)
        let occs = (0..<4).map { i in occ("\(i)", cal.date(byAdding: .day, value: 7*i, to: base)!, 4.0, "Gym Locker") }
        let now = day(2026, 3, 1)
        let result = SubscriptionDetector.detect(occs, options: .init(now: now))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].cadence, .weekly)
        XCTAssertGreaterThan(result[0].predictedNextCharge, now)
    }

    func test_freeTrialThenPaid_isOneSeriesWithTrialFlag() {
        let occs = [
            occ("0", day(2026, 1, 10), 0.0, "Disney Plus"),     // trial
            occ("1", day(2026, 2, 10), 7.99, "Disney Plus"),
            occ("2", day(2026, 3, 10), 7.99, "Disney Plus"),
            occ("3", day(2026, 4, 10), 7.99, "Disney Plus"),
        ]
        let result = SubscriptionDetector.detect(occs, options: .init(now: day(2026, 4, 15)))
        XCTAssertEqual(result.count, 1)
        let c = result[0]
        XCTAssertEqual(c.cadence, .monthly)
        XCTAssertTrue(c.hadTrial)
        XCTAssertEqual(c.amount, Decimal(7.99))   // representative excludes the 0 trial
        XCTAssertEqual(c.occurrenceCount, 4)
    }

    func test_variableAmountUtility_flagged() {
        let occs = [
            occ("1", day(2026, 1, 15), 40.0, "Elektrik OSHEE"),
            occ("2", day(2026, 2, 15), 55.0, "Elektrik OSHEE"),
            occ("3", day(2026, 3, 15), 48.0, "Elektrik OSHEE"),
        ]
        let result = SubscriptionDetector.detect(occs, options: .init(now: day(2026, 3, 20)))
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isVariableAmount)
        XCTAssertEqual(result[0].cadence, .monthly)
    }

    func test_irregularIntervals_notDetected() {
        let occs = [
            occ("1", day(2026, 1, 1), 5.0, "Random Cafe"),
            occ("2", day(2026, 1, 3), 5.0, "Random Cafe"),
            occ("3", day(2026, 2, 20), 5.0, "Random Cafe"),
        ]
        XCTAssertTrue(SubscriptionDetector.detect(occs, options: .init(now: day(2026, 3, 1))).isEmpty)
    }

    func test_sameDayChargesCollapseToOneOccurrence() {
        let occs = [
            occ("1", day(2026, 1, 5), 9.99, "Netflix"),
            occ("1b", day(2026, 1, 5), 9.99, "Netflix"),
            occ("2", day(2026, 2, 5), 9.99, "Netflix"),
        ]
        XCTAssertTrue(SubscriptionDetector.detect(occs, options: .init(now: day(2026, 2, 10))).isEmpty)
    }

    func test_differentCurrenciesDoNotMerge() {
        let occs = [
            occ("1", day(2026, 1, 5), 9.99, "Netflix", .all),
            occ("2", day(2026, 2, 5), 9.99, "Netflix", .all),
            occ("3", day(2026, 3, 5), 9.99, "Netflix", .all),
            occ("4", day(2026, 1, 5), 5.0, "Netflix", CurrencyCode("USD")),
            occ("5", day(2026, 2, 5), 5.0, "Netflix", CurrencyCode("USD")),
            occ("6", day(2026, 3, 5), 5.0, "Netflix", CurrencyCode("USD")),
        ]
        let result = SubscriptionDetector.detect(occs, options: .init(now: day(2026, 3, 10)))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.currency.rawValue)), ["ALL", "USD"])
    }

    func test_emptyAndUnknownMerchant_ignored() {
        let occs = [
            occ("1", day(2026, 1, 5), 9.99, "   "),
            occ("2", day(2026, 2, 5), 9.99, "4471"),   // all-numeric → normalizes to ""
        ]
        XCTAssertTrue(SubscriptionDetector.detect(occs, options: .init(now: day(2026, 3, 1))).isEmpty)
    }
}
