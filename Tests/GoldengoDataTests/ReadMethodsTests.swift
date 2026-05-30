import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class ReadMethodsTests: XCTestCase {
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
        let total = try await store.todayTotal()
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
        let total = try await store.todayTotal()
        XCTAssertEqual(total, 100)  // excludes yesterday and income
    }

    func test_todayTotal_filtersToRequestedCurrency() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        let today = Date.now
        ctx.insert(ExpenseRecord(amount: 100, currencyCode: "ALL", date: today, kind: .expense, source: .manual, dedupeKey: "x"))
        ctx.insert(ExpenseRecord(amount: 50, currencyCode: "EUR", date: today, kind: .expense, source: .manual, dedupeKey: "y"))
        try ctx.save()
        let store = IngestionStore(modelContainer: container)
        let lek = try await store.todayTotal(in: .all)
        let eur = try await store.todayTotal(in: .eur)
        XCTAssertEqual(lek, 100)
        XCTAssertEqual(eur, 50)
    }
}
