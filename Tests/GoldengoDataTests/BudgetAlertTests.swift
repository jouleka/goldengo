import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class BudgetAlertTests: XCTestCase {
    private func store() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }
    // Single-currency ALL data → conversion is identity. Rate table mirrors DashboardSummaryTests.
    private let rates = RateTable(base: CurrencyCode("USD"), rates: ["USD": 1, "ALL": 100, "EUR": 1],
                                 asOf: Date(timeIntervalSince1970: 1_780_444_800))

    func test_escalatesOnce_nearThenOver_thenSilent() async throws {
        let s = try store()
        try await s.setMonthlyBudget(categoryNamed: "Cigarettes", cap: 1000)

        _ = try await s.logManual(amount: 900, currency: .all, merchant: nil, categoryName: "Cigarettes")
        let near = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertEqual(near.map(\.level), [.near])

        let againSameLevel = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertTrue(againSameLevel.isEmpty)            // no re-fire at same level

        _ = try await s.logManual(amount: 300, currency: .all, merchant: nil, categoryName: "Cigarettes")
        let over = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertEqual(over.map(\.level), [.over])       // escalation near -> over fires once

        let silent = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertTrue(silent.isEmpty)
    }

    func test_noCap_neverAlerts() async throws {
        let s = try store()
        _ = try await s.logManual(amount: 9999, currency: .all, merchant: nil, categoryName: "Food")
        let alerts = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertTrue(alerts.isEmpty)
    }

    func test_newMonth_reArms() async throws {
        let s = try store()
        try await s.setMonthlyBudget(categoryNamed: "Food", cap: 1000)
        _ = try await s.logManual(amount: 1200, currency: .all, merchant: nil, categoryName: "Food")
        _ = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)   // fires over
        let cal = Calendar.current
        let nextMonth = cal.date(byAdding: .month, value: 1, to: .now)!
        // still over into the next month (recurring cap) -> re-arms and fires again once
        _ = try await s.logManual(amount: 1200, currency: .all, merchant: nil, categoryName: "Food", date: nextMonth)
        let next = try await s.evaluateBudgetAlerts(asOf: nextMonth, displayCurrency: .all, rates: rates)
        XCTAssertEqual(next.map(\.level), [.over])
    }
}
