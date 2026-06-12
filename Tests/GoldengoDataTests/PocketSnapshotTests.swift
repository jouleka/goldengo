import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class PocketSnapshotTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    func test_freshReconcile_isEven() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(7000, currency: .all, tally: nil, at: day(2026, 6, 10))
        let lines = try await store.pocketSnapshot(now: day(2026, 6, 10, hour: 18))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.currencyCode, "ALL")
        XCTAssertEqual(lines.first?.expected, 7000)
        XCTAssertEqual(lines.first?.confidence, .even)
    }

    func test_silentDaysWithMovementHistory_fog() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(7000, currency: .all, tally: nil, at: day(2026, 6, 1))
        // Movement history: cash spends on the 2nd and 3rd (~500/day median).
        _ = try await store.logManual(amount: 500, currency: .all, merchant: "Pazar",
                                      categoryName: nil, date: day(2026, 6, 2))
        _ = try await store.logManual(amount: 500, currency: .all, merchant: "Kafe",
                                      categoryName: nil, date: day(2026, 6, 3))
        // Then silence: last book movement Jun 3, now Jun 6 → 3 silent days.
        let lines = try await store.pocketSnapshot(now: day(2026, 6, 6))
        guard case .fogged(let width)? = lines.first?.confidence else {
            return XCTFail("3 silent days with movement history must fog, got \(String(describing: lines.first?.confidence))")
        }
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThan(width, 6000, "Capped well under one wallet at 3 days")
    }

    func test_cashEntry_resetsTheSilence() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(7000, currency: .all, tally: nil, at: day(2026, 6, 1))
        _ = try await store.logManual(amount: 500, currency: .all, merchant: "Pazar",
                                      categoryName: nil, date: day(2026, 6, 5))
        let lines = try await store.pocketSnapshot(now: day(2026, 6, 5, hour: 20))
        XCTAssertEqual(lines.first?.confidence, .even,
                       "The books moved with the hands today — the claim is current")
    }

    func test_staticCurrency_neverFogs() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(200, currency: .eur, tally: nil, at: day(2026, 6, 1))
        // No EUR cash movement EVER → fogging would be the app lying about its own blindness.
        let lines = try await store.pocketSnapshot(now: day(2026, 6, 9))
        let eur = lines.first { $0.currencyCode == "EUR" }
        XCTAssertEqual(eur?.confidence, .even)
    }

    func test_sharedPayload_writtenOnSave_andRoundTrips() async throws {
        let suite = "pocket-test-\(UUID().uuidString)"
        let summary = SharedSummary(suiteName: suite)
        let p = PocketPayload(lines: [
            .init(currencyCode: "ALL", expected: 7500, typicalCashDay: 500, lastMovement: day(2026, 6, 9)),
        ], hasWallet: true)
        summary.writePocketPayload(p)
        XCTAssertEqual(summary.readPocketPayload(), p)
        XCTAssertNil(SharedSummary(suiteName: "pocket-empty-\(UUID().uuidString)").readPocketPayload())
    }

    // Review: corrections must reach the lock screen. Delete/restore/update save directly —
    // each must republish the pocket payload, or the widget asserts pre-correction money.
    func test_editingPaths_republishThePocketClaim() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(9876, currency: .all, tally: nil, at: day(2026, 6, 1))
        let key = try await store.logManual(amount: 1111, currency: .all, merchant: "Pazar",
                                            categoryName: nil, date: day(2026, 6, 2))
        func publishedExpected() -> Decimal? {
            SharedSummary().readPocketPayload()?.lines.first { $0.currencyCode == "ALL" }?.expected
        }
        XCTAssertEqual(publishedExpected(), 8765, "log drains the published claim")

        try await store.deleteExpense(dedupeKey: key)
        XCTAssertEqual(publishedExpected(), 9876, "delete must republish, not freeze, the claim")

        try await store.restoreExpense(dedupeKey: key)
        XCTAssertEqual(publishedExpected(), 8765)

        try await store.updateExpense(dedupeKey: key, amount: 2222, merchant: "Pazar",
                                      categoryName: nil, date: day(2026, 6, 2),
                                      fundedBySourceID: FundingPin.wallet)
        XCTAssertEqual(publishedExpected(), 7654, "an amount edit must republish the claim")
    }

    // The user's question, pinned: a wallet change (reconcile) must land in the published
    // claim immediately — including the lower-reconcile path, where logDrift refreshes off the
    // OLD baseline first and the new-baseline refresh must win (one of the review's rejected
    // double-refresh findings; rejected precisely because the FINAL published value is correct).
    func test_walletChange_publishesTheClaimImmediately() async throws {
        let store = try makeStore()
        func publishedExpected() -> Decimal? {
            SharedSummary().readPocketPayload()?.lines.first { $0.currencyCode == "ALL" }?.expected
        }
        // First-ever set: the claim appears with exactly the typed number.
        _ = try await store.setWalletBalance(5000, currency: .all, tally: nil, at: day(2026, 6, 1))
        XCTAssertEqual(publishedExpected(), 5000, "a fresh wallet set must publish at once")
        XCTAssertEqual(SharedSummary().readPocketPayload()?.hasWallet, true)

        // Raise it — the higher baseline is published with no fabrication.
        _ = try await store.setWalletBalance(8000, currency: .all, tally: nil, at: day(2026, 6, 2))
        XCTAssertEqual(publishedExpected(), 8000, "a higher reconcile republishes the new baseline")

        // Lower it — a gap auto-logs (logDrift refreshes off the OLD baseline mid-call), then
        // the new baseline refresh must be what's left standing. No stale 8000, no double-count.
        let outcome = try await store.setWalletBalance(6500, currency: .all, tally: nil, at: day(2026, 6, 3))
        XCTAssertEqual(outcome.unaccountedLogged, 1500, "the 1 500 gap is logged Unaccounted")
        XCTAssertEqual(publishedExpected(), 6500,
                       "the lower reconcile's final published claim is the typed number, not the pre-gap value")
    }
}
