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
    private func balance(_ store: IngestionStore, _ code: String, now: Date) async throws -> Decimal? {
        try await store.walletBalances(now: now).first { $0.currencyCode == code }?.expectedNow
    }

    func test_firstSet_seedsBaseline_noEntryLogged() async throws {
        let store = try makeStore()
        let outcome = try await store.setWalletBalance(5000, currency: .all, tally: nil, at: day(2026, 6, 1))
        XCTAssertNil(outcome.expected, "No prior baseline — nothing to compare against")
        XCTAssertNil(outcome.unaccountedLogged)
        let b = try await balance(store, "ALL", now: day(2026, 6, 1, hour: 13))
        XCTAssertEqual(b, 5000)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 0, "Setting a baseline writes no expense rows")
    }

    func test_flows_v2_onlyCashTouchesTheWallet() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(5000, currency: .all, tally: nil, at: day(2026, 6, 1))
        // ATM withdrawal (transfer) → wallet inflow.
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "atm1", amount: 10000, currency: .all, date: day(2026, 6, 2),
            rawMerchant: "TERHEQJE ATM", kind: .transfer, accountRef: "statement"), source: .imported)
        // BANK income (the v1 bug): Freelance pay must NOT credit the wallet.
        try await store.logIncome(amount: 50000, currency: .all, sourceName: "Freelance",
                                  date: day(2026, 6, 2, hour: 9))
        // CASH-IN-HAND income: credits the wallet.
        try await store.logIncome(amount: 2000, currency: .all, sourceName: "Friday cash",
                                  date: day(2026, 6, 2, hour: 18), intoWallet: true)
        // Hand-logged spend (default cash) → wallet outflow.
        _ = try await store.logManual(amount: 350, currency: .all, merchant: "Mon Cheri",
                                      categoryName: nil, date: day(2026, 6, 3))
        // Hand-logged spend PINNED to a named source = bank-paid → NOT a wallet outflow.
        let sourceID = try await store.provenanceSnapshot(displayCurrency: .all).sources
            .first { $0.name == "Freelance" }?.id
        _ = try await store.logManual(amount: 4000, currency: .all, merchant: "Online order",
                                      categoryName: nil, date: day(2026, 6, 3),
                                      fundedBySourceID: sourceID)
        // Imported card spend → NOT a wallet outflow.
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "card1", amount: 7000, currency: .all, date: day(2026, 6, 3),
            rawMerchant: "Spar", kind: .expense, accountRef: "statement"), source: .imported)
        let b = try await balance(store, "ALL", now: day(2026, 6, 4))
        XCTAssertEqual(b, 5000 + 10000 + 2000 - 350,
                       "transfer + cash income in; default-cash spend out; bank income, pinned spend, card spend ignored")
    }

    func test_setLower_autoLogsUnaccounted_identityExcluded() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(5000, currency: .all, tally: nil, at: day(2026, 6, 1))
        let outcome = try await store.setWalletBalance(3600, currency: .all, tally: nil, at: day(2026, 6, 5))
        XCTAssertEqual(outcome.expected, 5000)
        XCTAssertEqual(outcome.unaccountedLogged, 1400,
                       "Lower than expected → one visible Unaccounted entry, no ceremony")
        let rows = try await store.recentExpenses(limit: 10)
        XCTAssertTrue(rows.contains { $0.dedupeKey.hasPrefix("drift:") && $0.amount == 1400 })
        let b = try await balance(store, "ALL", now: day(2026, 6, 6))
        XCTAssertEqual(b, 3600, "The typed amount IS the balance — the entry never re-drains it")
    }

    func test_setHigher_fabricatesNothing() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(5000, currency: .all, tally: nil, at: day(2026, 6, 1))
        let outcome = try await store.setWalletBalance(8000, currency: .all, tally: nil, at: day(2026, 6, 5))
        XCTAssertEqual(outcome.expected, 5000)
        XCTAssertNil(outcome.unaccountedLogged)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 0)
        let b = try await balance(store, "ALL", now: day(2026, 6, 6))
        XCTAssertEqual(b, 8000)
    }

    func test_setToDisplayedValue_logsNoSubUnitDrift() async throws {
        // ALL displays with 0 fraction digits. A flow residue below display precision (statement
        // amounts can carry decimals) must not turn "set it to exactly what the screen shows"
        // into a junk Unaccounted entry.
        let store = try makeStore()
        _ = try await store.setWalletBalance(5000, currency: .all, tally: nil, at: day(2026, 6, 1))
        _ = try await store.logManual(amount: Decimal(string: "0.4")!, currency: .all,
                                      merchant: "Residue", categoryName: nil, date: day(2026, 6, 2))
        // Books now expect 4999.6 — shown as "ALL 5,000". The user types 5000.
        let outcome = try await store.setWalletBalance(5000, currency: .all, tally: nil, at: day(2026, 6, 3))
        XCTAssertNil(outcome.unaccountedLogged, "No drift below what the user can see")
        let rows = try await store.recentExpenses(limit: 10)
        XCTAssertFalse(rows.contains { $0.dedupeKey.hasPrefix("drift:") })
    }

    func test_removeWalletCurrency_lineDisappears_reSetStartsFresh() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(5000, currency: .all, tally: nil, at: day(2026, 6, 1))
        _ = try await store.setWalletBalance(80, currency: .eur, tally: nil, at: day(2026, 6, 1))
        try await store.removeWalletCurrency(.eur)
        let codes = try await store.walletBalances(now: day(2026, 6, 2)).map(\.currencyCode)
        XCTAssertEqual(codes, ["ALL"], "The removed line is gone; other currencies untouched")
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 0, "Removing a tracked currency deletes the LINE, never money records")
        // WHY: re-tracking must start fresh — if the old baseline bled through, the first new set
        // would auto-log a bogus Unaccounted gap against balances the user stopped tracking.
        let outcome = try await store.setWalletBalance(50, currency: .eur, tally: nil, at: day(2026, 6, 3))
        XCTAssertNil(outcome.expected, "No prior baseline after removal — no drift comparison")
        let b = try await balance(store, "EUR", now: day(2026, 6, 4))
        XCTAssertEqual(b, 50)
    }

    func test_perCurrency_walletsAreIndependent() async throws {
        let store = try makeStore()
        _ = try await store.setWalletBalance(5000, currency: .all, tally: nil, at: day(2026, 6, 1))
        _ = try await store.setWalletBalance(120, currency: .eur, tally: nil, at: day(2026, 6, 1))
        _ = try await store.logManual(amount: 20, currency: .eur, merchant: "Hostel",
                                      categoryName: nil, date: day(2026, 6, 2))
        let all = try await balance(store, "ALL", now: day(2026, 6, 3))
        let eur = try await balance(store, "EUR", now: day(2026, 6, 3))
        XCTAssertEqual(all, 5000, "An EUR spend never touches the lek line")
        XCTAssertEqual(eur, 100)
    }

    func test_tallyInput_isJustAnotherWayToSetTheBalance() async throws {
        let store = try makeStore()
        var t = DenominationTally(); t.counts = [1000: 3, 500: 1]
        let outcome = try await store.setWalletBalance(t.total, currency: .all, tally: t, at: day(2026, 6, 1))
        XCTAssertNil(outcome.expected)
        let b = try await balance(store, "ALL", now: day(2026, 6, 2))
        XCTAssertEqual(b, 3500)
    }

    func test_reimport_convergesKindSiblings_neverDuplicates() async throws {
        // kind is baked into the composite dedupeKey: an ATM row imported PRE-feature persisted
        // as .expense; re-importing the same statement now maps it to .transfer. The sibling-kind
        // probe must converge the pair onto ONE record, retagged .transfer.
        let store = try makeStore()
        let asExpense = NormalizedTransaction(
            externalID: nil, amount: 10000, currency: .all, date: day(2026, 6, 2),
            rawMerchant: "TERHEQJE ATM", kind: .expense, accountRef: "statement")
        let asTransfer = NormalizedTransaction(
            externalID: nil, amount: 10000, currency: .all, date: day(2026, 6, 2),
            rawMerchant: "TERHEQJE ATM", kind: .transfer, accountRef: "statement")
        _ = try await store.ingest(asExpense, source: .imported)
        let outcome = try await store.ingest(asTransfer, source: .imported)
        XCTAssertEqual(outcome, .merged, "Same statement row — never a second record")
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1)
        let total = try await store.todayTotal(in: .all, rates: SeedRates.table)
        XCTAssertEqual(total, 0, "The converged record is a transfer — the old double-count heals")
        let reverse = try await store.ingest(asExpense, source: .imported)
        XCTAssertEqual(reverse, .merged)
        let totalAfter = try await store.todayTotal(in: .all, rates: SeedRates.table)
        XCTAssertEqual(totalAfter, 0, "Never downgraded back to spend")
    }

    func test_cashIncome_forUntrackedCurrency_seedsItsWalletLine() async throws {
        // "Cash in hand" must be VISIBLE immediately — a currency with no baseline would
        // swallow the inflow invisibly (review finding).
        let store = try makeStore()
        try await store.logIncome(amount: 50, currency: .eur, sourceName: "Tip",
                                  date: day(2026, 6, 2), intoWallet: true)
        let eur = try await balance(store, "EUR", now: day(2026, 6, 3))
        XCTAssertEqual(eur, 50, "A zero baseline is seeded just before the income, so the line shows it")
    }

    func test_v2_withdrawalDrainsBankSources_cashSpendDrainsOnlyWallet() async throws {
        let store = try makeStore()
        try await store.logIncome(amount: 50000, currency: .all, sourceName: "Freelance",
                                  date: day(2026, 6, 1, hour: 9))
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "atm1", amount: 10000, currency: .all, date: day(2026, 6, 2),
            rawMerchant: "TERHEQJE ATM", kind: .transfer, accountRef: "statement"), source: .imported)
        var snap = try await store.provenanceSnapshot(displayCurrency: .all)
        XCTAssertEqual(snap.sources.first { $0.name == "Freelance" }?.remaining, 40000,
                       "The withdrawal is the moment the bank-side source drains")
        // The cash spend drains ONLY the wallet — Freelance must not drop again.
        _ = try await store.logManual(amount: 2000, currency: .all, merchant: "Pazar",
                                      categoryName: nil, date: day(2026, 6, 3))
        snap = try await store.provenanceSnapshot(displayCurrency: .all)
        XCTAssertEqual(snap.sources.first { $0.name == "Freelance" }?.remaining, 40000,
                       "No double-drain: the money already left the bank at the ATM")
    }

    func test_transfers_stayOutOfSpendTotals() async throws {
        let store = try makeStore()
        _ = try await store.ingest(NormalizedTransaction(
            externalID: "atm1", amount: 10000, currency: .all, date: .now,
            rawMerchant: "TERHEQJE ATM", kind: .transfer, accountRef: "statement"), source: .imported)
        let total = try await store.todayTotal(in: .all, rates: SeedRates.table)
        XCTAssertEqual(total, 0, "A withdrawal is not spend")
    }
}
