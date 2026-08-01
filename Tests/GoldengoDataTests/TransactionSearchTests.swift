import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class TransactionSearchTests: XCTestCase {
    func test_searchFindsMerchantContextAndSplitCategoryAcrossAllTime() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let store = IngestionStore(modelContainer: container)
        _ = try await store.logManual(amount: 300, currency: .all, merchant: "SPAR Tirana",
                                      note: "Weekend basket", categoryName: "Other",
                                      date: .now.addingTimeInterval(-400 * 86_400), contextName: "Family",
                                      splits: [TransactionSplit(amount: 200, categoryName: "Groceries"),
                                               TransactionSplit(amount: 100, categoryName: "Household")])
        var criteria = TransactionSearchCriteria(); criteria.query = "spar"
        let merchantResults = try await store.searchTransactions(criteria)
        XCTAssertEqual(merchantResults.rows.count, 1)
        criteria.query = ""; criteria.contextName = "Family"; criteria.categoryName = "Household"
        let filteredResults = try await store.searchTransactions(criteria)
        XCTAssertEqual(filteredResults.rows.count, 1)
    }

    func test_searchSeparatesInvestmentFromConsumption() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let store = IngestionStore(modelContainer: container)
        _ = try await store.logManual(amount: 100, currency: .all, merchant: "Lunch", categoryName: "Food")
        _ = try await store.logManual(amount: 500, currency: .all, merchant: "Broker", categoryName: "Stocks & funds")
        var criteria = TransactionSearchCriteria(); criteria.scope = .invested
        let results = try await store.searchTransactions(criteria)
        XCTAssertEqual(results.rows.count, 1)
        XCTAssertEqual(results.rows.first?.merchantName, "Broker")
    }
}
