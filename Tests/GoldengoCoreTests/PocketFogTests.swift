import XCTest
import GoldengoCore

final class PocketFogTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func test_typicalCashDay_isMedianWithFloor() {
        XCTAssertEqual(PocketFog.typicalCashDay(dailyOutflows: [200, 800, 400], floor: 100), 400)
        XCTAssertEqual(PocketFog.typicalCashDay(dailyOutflows: [50, 60], floor: 300), 300,
                       "Thin/low history never makes fog grow absurdly slowly relative to the wallet")
        XCTAssertEqual(PocketFog.typicalCashDay(dailyOutflows: [], floor: 250), 250)
    }

    func test_silentDays_wholeUTCDays_neverNegative() {
        XCTAssertEqual(PocketFog.silentDays(from: day(2026, 6, 1), to: day(2026, 6, 1, hour: 20)), 0)
        XCTAssertEqual(PocketFog.silentDays(from: day(2026, 6, 1), to: day(2026, 6, 4)), 3)
        XCTAssertEqual(PocketFog.silentDays(from: day(2026, 6, 4), to: day(2026, 6, 1)), 0,
                       "A future-dated movement must clamp, not go negative")
    }

    func test_confidence_states() {
        // Day zero: the books were just reconciled — the claim is exact.
        XCTAssertEqual(PocketFog.confidence(silentDays: 0, typicalCashDay: 500, walletTotal: 7000), .even)
        // Linear growth: 3 silent days at ~500/day → ±1500.
        XCTAssertEqual(PocketFog.confidence(silentDays: 3, typicalCashDay: 500, walletTotal: 7000),
                       .fogged(width: 1500))
        // Cap (assassin guard 1): past ~one wallet the ±N is meaningless — degrade to plain words.
        XCTAssertEqual(PocketFog.confidence(silentDays: 20, typicalCashDay: 500, walletTotal: 7000), .lost)
        // An exactly-zero wallet cannot drain: the books are EXACT, not blind. "Lost track"
        // here would be a false confession the user can never durably clear (review).
        XCTAssertEqual(PocketFog.confidence(silentDays: 2, typicalCashDay: 500, walletTotal: 0), .even)
        // Negative balance: the books are provably wrong — that IS lost.
        XCTAssertEqual(PocketFog.confidence(silentDays: 2, typicalCashDay: 500, walletTotal: -100), .lost)
        // No movement rate (static currency handled store-side, but the math is safe anyway).
        XCTAssertEqual(PocketFog.confidence(silentDays: 5, typicalCashDay: 0, walletTotal: 7000), .even)
    }

    func test_payload_codableRoundTrip() throws {
        let p = PocketPayload(lines: [
            .init(currencyCode: "ALL", expected: 7500, typicalCashDay: 500, lastMovement: day(2026, 6, 9)),
            .init(currencyCode: "EUR", expected: 60, typicalCashDay: 0, lastMovement: day(2026, 4, 14)),
        ], hasWallet: true)
        let decoded = try JSONDecoder().decode(PocketPayload.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }

    // The frozen-claim regression (review, HIGH): one payload, rendered at later dates, must
    // show fog appearing and deepening WITHOUT any new app-side save — silent days are exactly
    // the days with no saves, so the widget itself has to advance the claim.
    func test_content_fogAdvancesWithRenderDate_withoutRecompose() {
        let reconciled = day(2026, 6, 1)
        let p = PocketPayload(lines: [
            .init(currencyCode: "ALL", expected: 7000, typicalCashDay: 500, lastMovement: reconciled),
        ], hasWallet: true)
        let exact = Money(amount: 7000, currency: CurrencyCode("ALL")).formatted()

        let day0 = p.content(at: day(2026, 6, 1, hour: 18))
        XCTAssertEqual(day0.revealedInline, exact)
        XCTAssertTrue(day0.hiddenInline.hasPrefix("even since"))

        let day3 = p.content(at: day(2026, 6, 4))
        XCTAssertEqual(day3.revealedInline, "~" + exact, "3 silent days must read as a blurred claim")
        XCTAssertTrue(day3.hiddenInline.hasPrefix("losing track since"))

        let day20 = p.content(at: day(2026, 6, 21))
        XCTAssertEqual(day20.revealedInline, "lost track — tap when your wallet's out",
                       "Past the cap the claim degrades to plain words — never a stale exact number")
    }

    // Review (HIGH): .lost must never render a number anywhere — a bare amount at maximum
    // drift is indistinguishable from freshly reconciled, the exact inversion guard 1 forbids.
    func test_content_lostRendersWordsNeverNumbers() {
        let p = PocketPayload(lines: [
            .init(currencyCode: "ALL", expected: 7000, typicalCashDay: 500, lastMovement: day(2026, 5, 1)),
        ], hasWallet: true)
        let c = p.content(at: day(2026, 6, 10))   // 40 silent days at 500/day ≫ 7000
        let amountText = Money(amount: 7000, currency: CurrencyCode("ALL")).formatted()
        XCTAssertFalse(c.revealedInline.contains(amountText))
        XCTAssertFalse(c.revealedLines.joined().contains(amountText))
        XCTAssertEqual(c.revealedLines, ["Lek — lost track — tap when your wallet's out"])
        XCTAssertEqual(c.hiddenLines, c.revealedLines, "There is no number to reveal in .lost")
    }

    // Review: the privacy inline must speak for the WORST currency — "even" while another
    // tracked currency is lost hides exactly what the feature exists to confess.
    func test_content_hiddenInline_reflectsWorstCurrency() {
        let p = PocketPayload(lines: [
            .init(currencyCode: "ALL", expected: 7500, typicalCashDay: 0, lastMovement: day(2026, 6, 9)),   // static, even
            .init(currencyCode: "EUR", expected: 60, typicalCashDay: 10, lastMovement: day(2026, 5, 1)),    // long lost
        ], hasWallet: true)
        let c = p.content(at: day(2026, 6, 10))
        XCTAssertEqual(c.hiddenInline, "lost track — tap when your wallet's out")
        XCTAssertTrue(c.revealedInline.contains("Euro lost track"),
                      "Multi-currency revealed inline carries the lost state in words, not a number")
        XCTAssertFalse(c.revealedInline.contains(Money(amount: 60, currency: .eur).formatted()))
    }

    // Review: a bare weekday is ambiguous past one week — "even since Tue" must become a real
    // date once the movement is old (static currencies stay even for months by design).
    func test_content_sinceLabel_fallsBackToDateWhenOld() {
        let old = day(2026, 4, 14)   // a Tuesday, ~8 weeks back
        let p = PocketPayload(lines: [
            .init(currencyCode: "EUR", expected: 200, typicalCashDay: 0, lastMovement: old),
        ], hasWallet: true)
        let c = p.content(at: day(2026, 6, 10))
        let dated = old.formatted(.dateTime.month(.abbreviated).day())
        XCTAssertEqual(c.hiddenInline, "even since \(dated)")

        let recent = day(2026, 6, 8)
        let p2 = PocketPayload(lines: [
            .init(currencyCode: "EUR", expected: 200, typicalCashDay: 0, lastMovement: recent),
        ], hasWallet: true)
        let weekday = recent.formatted(.dateTime.weekday(.abbreviated))
        XCTAssertEqual(p2.content(at: day(2026, 6, 10)).hiddenInline, "even since \(weekday)")
    }

    func test_content_emptyPayload_invitesSetup() {
        let c = PocketPayload(lines: [], hasWallet: false).content(at: day(2026, 6, 10))
        XCTAssertEqual(c.revealedInline, "Set your wallet")
        XCTAssertEqual(c.hiddenInline, "Set your wallet")
        XCTAssertTrue(c.revealedLines.isEmpty)
    }
}
