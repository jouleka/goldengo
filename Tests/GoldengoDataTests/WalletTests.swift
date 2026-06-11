import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class WalletTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }
    private func tally(_ counts: [Int: Int]) -> DenominationTally {
        var t = DenominationTally(); t.counts = counts; return t
    }

    func test_firstCount_seedsBaseline_noDrift() async throws {
        let store = try makeStore()
        let outcome = try await store.recordWalletCount(tally([1000: 5]), at: day(2026, 6, 1))
        XCTAssertEqual(outcome.countedTotal, 5000)
        XCTAssertNil(outcome.expected, "No prior baseline — nothing to compare against")
        XCTAssertNil(outcome.drift)
        let snap = try await store.walletSnapshot(now: day(2026, 6, 1, hour: 13))
        XCTAssertEqual(snap?.expectedNow, 5000)
    }

    func test_flows_moveTheExpectedBalance() async throws {
        let store = try makeStore()
        _ = try await store.recordWalletCount(tally([1000: 5]), at: day(2026, 6, 1))
        // ATM withdrawal arrives via import as a transfer → inflow.
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "atm1", amount: 10000, currency: .all, date: day(2026, 6, 2),
            rawMerchant: "TERHEQJE ATM", kind: .transfer, accountRef: "statement"), source: .imported)
        // Cash income in hand → inflow.
        try await store.logIncome(amount: 2000, currency: .all, sourceName: "Friday cash",
                                  date: day(2026, 6, 2, hour: 18))
        // Hand-logged spend → outflow. Imported card expense → NOT an outflow.
        _ = try await store.logManual(amount: 350, currency: .all, merchant: "Mon Cheri",
                                      categoryName: nil, date: day(2026, 6, 3))
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "card1", amount: 4000, currency: .all, date: day(2026, 6, 3),
            rawMerchant: "Spar", kind: .expense, accountRef: "statement"), source: .imported)
        let snap = try await store.walletSnapshot(now: day(2026, 6, 4))
        XCTAssertEqual(snap?.expectedNow, 5000 + 10000 + 2000 - 350,
                       "transfer + cash income in, manual spend out, card spend ignored")
    }

    func test_secondCount_reportsDrift_andResetsBaseline() async throws {
        let store = try makeStore()
        _ = try await store.recordWalletCount(tally([1000: 5]), at: day(2026, 6, 1))
        _ = try await store.logManual(amount: 600, currency: .all, merchant: nil,
                                      categoryName: nil, date: day(2026, 6, 2))
        // Expected 4400; user counts only 3000 → 1400 slipped by.
        let outcome = try await store.recordWalletCount(tally([2000: 1, 1000: 1]), at: day(2026, 6, 5))
        XCTAssertEqual(outcome.expected, 4400)
        XCTAssertEqual(outcome.drift, -1400)
        let snap = try await store.walletSnapshot(now: day(2026, 6, 6))
        XCTAssertEqual(snap?.expectedNow, 3000, "The count is truth — baseline reset regardless of drift choice")
    }

    func test_driftEntry_isIdentityExcluded_fromWalletMath() async throws {
        let store = try makeStore()
        _ = try await store.recordWalletCount(tally([1000: 3]), at: day(2026, 6, 5))
        try await store.logDrift(amount: 1400, at: day(2026, 6, 5, hour: 13))
        let snap = try await store.walletSnapshot(now: day(2026, 6, 6))
        XCTAssertEqual(snap?.expectedNow, 3000,
                       "The street-money entry explains the PAST — it must never re-drain the wallet")
        // …but it IS an ordinary visible expense.
        let rows = try await store.recentExpenses(limit: 10)
        XCTAssertTrue(rows.contains { $0.dedupeKey.hasPrefix("drift:") && $0.amount == 1400 })
    }

    func test_transfers_stayOutOfSpendTotals() async throws {
        let store = try makeStore()
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "atm1", amount: 10000, currency: .all, date: .now,
            rawMerchant: "TERHEQJE ATM", kind: .transfer, accountRef: "statement"), source: .imported)
        let total = try await store.todayTotal(in: .all, rates: SeedRates.table)
        XCTAssertEqual(total, 0, "A withdrawal is not spend — the double-count ends here")
    }

    func test_nonALLFlows_doNotTouchTheLekWallet() async throws {
        let store = try makeStore()
        _ = try await store.recordWalletCount(tally([1000: 3]), at: day(2026, 6, 1))
        _ = try await store.logManual(amount: 20, currency: .eur, merchant: "Hostel",
                                      categoryName: nil, date: day(2026, 6, 2))
        let snap = try await store.walletSnapshot(now: day(2026, 6, 3))
        XCTAssertEqual(snap?.expectedNow, 3000, "v1 wallet is ALL-only")
    }
}
