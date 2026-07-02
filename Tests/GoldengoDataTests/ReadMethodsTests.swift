import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class ReadMethodsTests: XCTestCase {
    // 1 USD = 100 ALL = 1 EUR, so 1 EUR = 100 ALL.
    private let rates = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1],
                                  asOf: Date(timeIntervalSince1970: 1_780_444_800))

    func test_recentCategoryNames_mostRecentFirst_distinct_skipsArchived() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.logManual(amount: 5, currency: .all, merchant: "a", categoryName: "Coffee", date: base)
        _ = try await store.logManual(amount: 5, currency: .all, merchant: "b", categoryName: "Books", date: base.addingTimeInterval(60))
        _ = try await store.logManual(amount: 5, currency: .all, merchant: "c", categoryName: "Coffee", date: base.addingTimeInterval(120))
        let gone = try await store.logManual(amount: 5, currency: .all, merchant: "d", categoryName: "Vice", date: base.addingTimeInterval(180))
        try await store.deleteExpense(dedupeKey: gone)
        let names = try await store.recentCategoryNames()
        // WHY: the chip row is a habit surface — most-recently-USED first, one chip per
        // category, and deleted history must not resurrect chips.
        XCTAssertEqual(names, ["Coffee", "Books"])
    }

    func test_recentExpenses_returnsAllNonArchived() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 100, currency: .all, merchant: "A", categoryName: nil)
        try await store.logManual(amount: 200, currency: .all, merchant: "B", categoryName: nil)
        let recents = try await store.recentExpenses(limit: 10)
        XCTAssertEqual(recents.count, 2)
        XCTAssertEqual(Set(recents.map(\.amount)), [100, 200])
    }

    func test_todayTotal_sumsTodaysExpenses() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logManual(amount: 100, currency: .all, merchant: nil, categoryName: nil)
        try await store.logManual(amount: 250, currency: .all, merchant: nil, categoryName: nil)
        let total = try await store.todayTotal(rates: rates)
        XCTAssertEqual(total, 350)
    }

    func test_recentExpenses_newestFirst_andRespectsLimit() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        for i in 0..<3 {
            ctx.insert(ExpenseRecord(amount: Decimal((i + 1) * 100), currencyCode: "ALL",
                date: base.addingTimeInterval(Double(i) * 86_400),
                kind: .expense, source: .manual, dedupeKey: "k\(i)"))
        }
        try ctx.save()
        let store = IngestionStore(modelContainer: container)
        let recent = try await store.recentExpenses(limit: 2)
        XCTAssertEqual(recent.count, 2)                  // limit respected
        XCTAssertEqual(recent.map(\.amount), [300, 200]) // newest (latest date) first
    }

    func test_todayTotal_excludesPastDaysAndNonExpenseKinds() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        let today = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        ctx.insert(ExpenseRecord(amount: 100, currencyCode: "ALL", date: today, kind: .expense, source: .manual, dedupeKey: "a"))
        ctx.insert(ExpenseRecord(amount: 999, currencyCode: "ALL", date: yesterday, kind: .expense, source: .manual, dedupeKey: "b"))
        ctx.insert(ExpenseRecord(amount: 500, currencyCode: "ALL", date: today, kind: .income, source: .manual, dedupeKey: "c"))
        try ctx.save()
        let store = IngestionStore(modelContainer: container)
        let total = try await store.todayTotal(rates: rates)
        XCTAssertEqual(total, 100)  // excludes yesterday and income
    }

    func test_todayTotal_convertsAllExpensesToRequestedCurrency() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        let today = Date.now
        ctx.insert(ExpenseRecord(amount: 100, currencyCode: "ALL", date: today, kind: .expense, source: .manual, dedupeKey: "x"))
        ctx.insert(ExpenseRecord(amount: 50, currencyCode: "EUR", date: today, kind: .expense, source: .manual, dedupeKey: "y"))
        try ctx.save()
        let store = IngestionStore(modelContainer: container)
        // 1 EUR = 100 ALL. In lek: 100 + 50*100 = 5100. In euro: 100/100 + 50 = 51.
        let lek = try await store.todayTotal(in: .all, rates: rates)
        let eur = try await store.todayTotal(in: .eur, rates: rates)
        XCTAssertEqual(lek, 5100)
        XCTAssertEqual(eur, 51)
    }
}
