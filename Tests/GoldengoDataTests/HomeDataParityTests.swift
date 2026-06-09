import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class HomeDataParityTests: XCTestCase {
    func test_homeData_matchesGranularMethods() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        // Income source, a today expense, and a 7-day daily pattern (yields a ghost), mixed kinds.
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister")
        try await store.logManual(amount: 200, currency: .all, merchant: "Coffee", categoryName: "Coffee", date: .now)
        for k in stride(from: 7, through: 1, by: -1) {
            try await store.logManual(amount: 150, currency: .all, merchant: "Bus", categoryName: nil,
                                      date: Date().addingTimeInterval(Double(-k) * 86_400))
        }
        let rates = SeedRates.table
        let now = Date()

        let data = try await store.homeData(in: .all, rates: rates, now: now, topCategoryLimit: 4)
        let recent = try await store.recentExpenses(limit: 50)
        let today = try await store.todayTotal(in: .all, rates: rates)
        let summary = try await store.dashboardSummary(in: .all, rates: rates, now: now, topCategoryLimit: 4)
        let ghosts = try await store.rhythmGhosts(now: now)

        XCTAssertEqual(data.rows, recent, "recent rows (incl. fundedBy) must match recentExpenses")
        XCTAssertEqual(data.todayTotal, today, "today total must match todayTotal")
        XCTAssertEqual(data.summary, summary, "summary must match dashboardSummary")
        XCTAssertEqual(data.ghosts, ghosts, "ghosts must match rhythmGhosts")
        XCTAssertTrue(data.ghosts.contains { $0.displayName == "Bus" }, "the daily pattern surfaces a ghost")
    }
}
