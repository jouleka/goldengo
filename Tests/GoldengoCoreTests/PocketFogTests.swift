import XCTest
import GoldengoCore

final class PocketFogTests: XCTestCase {
    func test_typicalCashDay_isMedianWithFloor() {
        XCTAssertEqual(PocketFog.typicalCashDay(dailyOutflows: [200, 800, 400], floor: 100), 400)
        XCTAssertEqual(PocketFog.typicalCashDay(dailyOutflows: [50, 60], floor: 300), 300,
                       "Thin/low history never makes fog grow absurdly slowly relative to the wallet")
        XCTAssertEqual(PocketFog.typicalCashDay(dailyOutflows: [], floor: 250), 250)
    }

    func test_confidence_states() {
        // Day zero: the books were just reconciled — the claim is exact.
        XCTAssertEqual(PocketFog.confidence(silentDays: 0, typicalCashDay: 500, walletTotal: 7000), .even)
        // Linear growth: 3 silent days at ~500/day → ±1500.
        XCTAssertEqual(PocketFog.confidence(silentDays: 3, typicalCashDay: 500, walletTotal: 7000),
                       .fogged(width: 1500))
        // Cap (assassin guard 1): past ~one wallet the ±N is meaningless — degrade to plain words.
        XCTAssertEqual(PocketFog.confidence(silentDays: 20, typicalCashDay: 500, walletTotal: 7000), .lost)
        // Zero/negative wallet with silence: nothing falsifiable to claim → lost, not ±0.
        XCTAssertEqual(PocketFog.confidence(silentDays: 2, typicalCashDay: 500, walletTotal: 0), .lost)
        // No movement rate (static currency handled store-side, but the math is safe anyway).
        XCTAssertEqual(PocketFog.confidence(silentDays: 5, typicalCashDay: 0, walletTotal: 7000), .even)
    }

    func test_payload_codableRoundTrip() throws {
        let p = PocketPayload(revealedInline: "7 500 L · 60 €", hiddenInline: "even since Tue",
                              revealedLines: ["7 500 L — even since Tue", "60 € — even"],
                              hiddenLines: ["Lek — even since Tue", "Euro — even"],
                              hasWallet: true)
        let decoded = try JSONDecoder().decode(PocketPayload.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }
}
