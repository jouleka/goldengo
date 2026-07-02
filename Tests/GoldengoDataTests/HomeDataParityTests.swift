import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class HomeDataParityTests: XCTestCase {
    func test_homeData_matchesGranularMethods() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        // Income source, a today expense, and a 7-day daily pattern (yields a ghost), mixed kinds.
        let now = Date()
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!

        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister")
        try await store.logManual(amount: 200, currency: .all, merchant: "Coffee", categoryName: "Coffee", date: .now)
        for k in stride(from: 7, through: 1, by: -1) {
            try await store.logManual(amount: 150, currency: .all, merchant: "Bus", categoryName: nil,
                                      date: Date().addingTimeInterval(Double(-k) * 86_400))
        }
        // A deliberate PRIOR-month expense. Home is now scoped to the current month (older spend lives
        // in History), so this must appear in the rolling recentExpenses list but NOT in homeData.rows.
        try await store.logManual(amount: 99, currency: .all, merchant: "LastMonth", categoryName: nil,
                                  date: monthStart.addingTimeInterval(-5 * 86_400))
        let rates = SeedRates.table

        let data = try await store.homeData(in: .all, rates: rates, now: now, topCategoryLimit: 4)
        let recent = try await store.recentExpenses(limit: 50)
        let today = try await store.todayTotal(in: .all, rates: rates)
        let summary = try await store.dashboardSummary(in: .all, rates: rates, now: now, topCategoryLimit: 4)
        let ghosts = try await store.rhythmGhosts(now: now)

        // Home's Recent is the current month only — i.e. recentExpenses scoped to this month. Filtering
        // both sides by the same `monthStart` keeps the parity check independent of the wall clock.
        XCTAssertEqual(data.rows, recent.filter { $0.date >= monthStart },
                       "Home rows are recentExpenses scoped to the current month (incl. fundedBy)")
        XCTAssertTrue(recent.contains { $0.merchantName == "LastMonth" }, "recentExpenses keeps older months")
        XCTAssertFalse(data.rows.contains { $0.merchantName == "LastMonth" },
                       "Home drops older months — they're reached via History, not the home list")
        XCTAssertEqual(data.todayTotal, today, "today total must match todayTotal")
        XCTAssertEqual(data.summary, summary, "summary must match dashboardSummary")
        XCTAssertEqual(data.ghosts, ghosts, "ghosts must match rhythmGhosts")
        XCTAssertTrue(data.ghosts.contains { $0.displayName == "Bus" }, "the daily pattern surfaces a ghost")
    }
}
