import XCTest
@testable import GoldengoCore

final class RhythmDetectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private func opts() -> RhythmDetector.Options { .init(now: now) }
    private func occ(_ daysAgo: Int, amount: Decimal, merchant: String = "Coffee") -> TransactionOccurrence {
        TransactionOccurrence(id: "o\(daysAgo)-\(merchant)", date: now.addingTimeInterval(Double(-daysAgo) * 86_400),
                              amount: amount, currency: .all, merchant: merchant)
    }

    func test_detectsStrongDailyPattern() {
        let series = (0...7).map { occ($0, amount: 200) }
        let p = RhythmDetector.detect(series, options: opts())
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.first?.amount, 200)
        XCTAssertEqual(p.first?.normalizedMerchant, "COFFEE")
        XCTAssertGreaterThanOrEqual(p.first?.confidence ?? 0, 0.6)
    }

    func test_medianAmount_whenAmountsVary() {
        let amts: [Decimal] = [180, 200, 200, 200, 220, 200]
        let series = amts.enumerated().map { occ($0.offset, amount: $0.element) }
        XCTAssertEqual(RhythmDetector.detect(series, options: opts()).first?.amount, 200)
    }

    func test_rejectsWeekly() {
        let series = [0, 7, 14, 21].map { occ($0, amount: 200) }
        XCTAssertTrue(RhythmDetector.detect(series, options: opts()).isEmpty)
    }

    func test_rejectsTooFewOccurrences() {
        let series = (0...3).map { occ($0, amount: 200) }
        XCTAssertTrue(RhythmDetector.detect(series, options: opts()).isEmpty)
    }

    func test_rejectsStale_notActive() {
        let series = (10...17).map { occ($0, amount: 200) }
        XCTAssertTrue(RhythmDetector.detect(series, options: opts()).isEmpty)
    }

    func test_rejectsSporadic_lowRegularity() {
        let series = [occ(0, amount: 200), occ(1, amount: 200), occ(2, amount: 200),
                      occ(3, amount: 200), occ(4, amount: 200), occ(12, amount: 200)]
        XCTAssertTrue(RhythmDetector.detect(series, options: opts()).isEmpty)
    }

    func test_recencyWindow_excludesOldOccurrences() {
        let series = (30...37).map { occ($0, amount: 200) }
        XCTAssertTrue(RhythmDetector.detect(series, options: opts()).isEmpty)
    }
}
