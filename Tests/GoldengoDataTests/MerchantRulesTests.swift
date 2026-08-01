import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class MerchantRulesTests: XCTestCase {
    func test_ruleCategorizesFutureTransactionsAndCanBeRemoved() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.setMerchantRule(merchantName: "CONAD Market 42", categoryName: "Groceries")

        _ = try await store.logManual(amount: 1_200, currency: .all,
                                      merchant: "Conad Market 99", categoryName: nil)
        var rows = try await store.recentExpenses()
        XCTAssertEqual(rows.first?.categoryName, "Groceries")
        let rules = try await store.merchantRules()
        XCTAssertEqual(rules.first?.categoryName, "Groceries")
        let ruleID = try XCTUnwrap(rules.first?.id)
        try await store.deleteMerchantRule(id: ruleID)
        _ = try await store.logManual(amount: 500, currency: .all,
                                      merchant: "Conad Market 7", categoryName: nil)
        rows = try await store.recentExpenses()
        XCTAssertEqual(rows.first?.categoryName, "Other")
        let rulesAfterDelete = try await store.merchantRules()
        XCTAssertTrue(rulesAfterDelete.isEmpty)
    }
}
