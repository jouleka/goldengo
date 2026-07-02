import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class LoanStoreTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    func test_lend_findOrCreatesPerson_balancesDerive() async throws {
        let store = try makeStore()
        try await store.lend(amount: 5000, currency: .all, personName: "Andi", date: day(2026, 6, 1))
        try await store.lend(amount: 1000, currency: .all, personName: " andi ", date: day(2026, 6, 10))
        let loans = try await store.loanBalances()
        // WHY: one person = one claim, however their name is typed — two "Andi" cards
        // would mean neither shows what he actually owes.
        XCTAssertEqual(loans.count, 1)
        XCTAssertEqual(loans.first?.lentTotal, 6000)
        XCTAssertEqual(loans.first?.remaining, 6000)
        XCTAssertEqual(loans.first?.sinceDate, day(2026, 6, 1))
        XCTAssertEqual(loans.first?.lastEventDate, day(2026, 6, 10))
    }

    func test_repayment_shrinksClaim_strictGuardRejectsOverpay() async throws {
        let store = try makeStore()
        try await store.lend(amount: 5000, currency: .all, personName: "Andi", date: day(2026, 6, 1))
        let pre = try await store.loanBalances()
        let id = try XCTUnwrap(pre.first?.id)
        try await store.logRepayment(amount: 2000, loanID: id, date: day(2026, 6, 15))
        var loans = try await store.loanBalances()
        XCTAssertEqual(loans.first?.remaining, 3000)
        // WHY strict: a payback above the debt isn't a payback — a friend's tip is income,
        // and silently absorbing it would fabricate a negative claim.
        try await store.logRepayment(amount: 9999, loanID: id, date: day(2026, 6, 16))
        try await store.logRepayment(amount: 0, loanID: id, date: day(2026, 6, 16))
        loans = try await store.loanBalances()
        XCTAssertEqual(loans.first?.remaining, 3000, "Over/zero paybacks are refused")
    }

    func test_renameLoan_keepsBalance_refusesLiveDuplicate() async throws {
        let store = try makeStore()
        try await store.lend(amount: 100, currency: .eur, personName: "Andi", date: day(2026, 6, 1))
        try await store.lend(amount: 50, currency: .eur, personName: "Era", date: day(2026, 6, 1))
        let loans = try await store.loanBalances()
        let id = try XCTUnwrap(loans.first { $0.personName == "Andi" }?.id)
        try await store.renameLoan(id: id, to: "Andi B.")
        var after = try await store.loanBalances()
        XCTAssertEqual(after.first { $0.personName == "Andi B." }?.remaining, 100,
                       "Balances key on the stable id — a rename never moves money")
        try await store.renameLoan(id: id, to: " era ")
        after = try await store.loanBalances()
        XCTAssertEqual(Set(after.map(\.personName)), ["Andi B.", "Era"],
                       "Case-insensitive collision with a live person is refused")
    }

    func test_deleteLoan_archivesClaimAndEvents_reLendStartsFresh() async throws {
        let store = try makeStore()
        try await store.lend(amount: 100, currency: .eur, personName: "Andi", date: day(2026, 6, 1))
        let pre = try await store.loanBalances()
        let id = try XCTUnwrap(pre.first?.id)
        try await store.deleteLoan(id: id)
        let empty = try await store.loanBalances()
        XCTAssertTrue(empty.isEmpty)
        // WHY: the claim and its history leave together — a re-created person must start
        // fresh, not resurrect the archived 100.
        try await store.lend(amount: 30, currency: .eur, personName: "Andi", date: day(2026, 6, 2))
        let fresh = try await store.loanBalances()
        XCTAssertEqual(fresh.first?.remaining, 30)
    }

    func test_forgive_logsVisibleGiftExpense_archivesLoan() async throws {
        let store = try makeStore()
        try await store.lend(amount: 5000, currency: .all, personName: "Andi", date: day(2026, 6, 1))
        let pre = try await store.loanBalances()
        let id = try XCTUnwrap(pre.first?.id)
        try await store.logRepayment(amount: 2000, loanID: id, date: day(2026, 6, 10))
        try await store.forgiveLoan(id: id, date: day(2026, 6, 20))
        let loans = try await store.loanBalances()
        XCTAssertTrue(loans.isEmpty, "A forgiven claim stops being tracked")
        // WHY: no silent write-offs — forgiveness is the moment the money became spending,
        // so it must appear as one visible, deletable expense.
        let rows = try await store.recentExpenses(limit: 10)
        let gift = rows.first { $0.dedupeKey.hasPrefix("forgive:") }
        XCTAssertEqual(gift?.amount, 3000)
        XCTAssertEqual(gift?.kind, .expense)
        XCTAssertEqual(gift?.categoryName, "Gifts")
    }
}
