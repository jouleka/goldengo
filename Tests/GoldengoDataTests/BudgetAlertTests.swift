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
        try await s.setMonthlyBudget(categoryNamed: "Cigarettes", cap: 1000, currency: .all)

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
        try await s.setMonthlyBudget(categoryNamed: "Food", cap: 1000, currency: .all)
        _ = try await s.logManual(amount: 1200, currency: .all, merchant: nil, categoryName: "Food")
        _ = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)   // fires over
        let cal = Calendar.current
        let nextMonth = cal.date(byAdding: .month, value: 1, to: .now)!
        // still over into the next month (recurring cap) -> re-arms and fires again once
        _ = try await s.logManual(amount: 1200, currency: .all, merchant: nil, categoryName: "Food", date: nextMonth)
        let next = try await s.evaluateBudgetAlerts(asOf: nextMonth, displayCurrency: .all, rates: rates)
        XCTAssertEqual(next.map(\.level), [.over])
    }

    func test_deEscalation_withinMonth_doesNotReFire_norLowerStoredLevel() async throws {
        // Monotonic-within-month guarantee: once the "over" alert has fired, a mid-month dip below
        // the cap (here via raising the cap; a refund would do the same) must NOT fire again, and must
        // NOT reset the dedupe state — so dropping back over must stay silent (proves stored level held).
        let s = try store()
        try await s.setMonthlyBudget(categoryNamed: "Food", cap: 1000, currency: .all)
        _ = try await s.logManual(amount: 1200, currency: .all, merchant: nil, categoryName: "Food")
        let over = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertEqual(over.map(\.level), [.over])                       // armed at over

        try await s.setMonthlyBudget(categoryNamed: "Food", cap: 2000, currency: .all)   // 1200/2000 → ok (de-escalated)
        let dip = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertTrue(dip.isEmpty)                                       // de-escalation fires nothing

        try await s.setMonthlyBudget(categoryNamed: "Food", cap: 1000, currency: .all)   // 1200/1000 → over again
        let backOver = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertTrue(backOver.isEmpty)                                  // stored level never lowered → no re-fire
    }

    func test_capWithZeroSpend_thenLaterEscalation_stillFires() async throws {
        // A cap set with no spend yet must not fire, but must not "swallow" a later escalation either.
        let s = try store()
        try await s.setMonthlyBudget(categoryNamed: "Coffee", cap: 1000, currency: .all)
        let none = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertTrue(none.isEmpty)                                      // zero spend → nothing

        _ = try await s.logManual(amount: 1100, currency: .all, merchant: nil, categoryName: "Coffee")
        let over = try await s.evaluateBudgetAlerts(asOf: .now, displayCurrency: .all, rates: rates)
        XCTAssertEqual(over.map(\.level), [.over])                       // baseline didn't swallow escalation
    }
}
