import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class LogAutomaticTests: XCTestCase {
    func test_logAutomatic_createsAutomaticSourcedExpense_withMerchant() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 1500, currency: .all, merchant: "Spar", categoryName: nil)
        let recents = try await store.recentExpenses(limit: 10)
        XCTAssertEqual(recents.count, 1)
        XCTAssertEqual(recents.first?.source, .automatic)
        XCTAssertEqual(recents.first?.merchantName, "Spar")
        XCTAssertEqual(recents.first?.amount, 1500)
        // Unknown merchant with no category → the "Other" fallback (never silently uncategorized).
        XCTAssertEqual(recents.first?.categoryName, "Other")
    }

    func test_logAutomatic_twoIdenticalCalls_neverCollapse() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await store.logAutomatic(amount: 300, currency: .all, merchant: "Coffee", categoryName: nil)
        _ = try await store.logAutomatic(amount: 300, currency: .all, merchant: "Coffee", categoryName: nil)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 2, "Each tap is a distinct purchase — unique keys, never merged.")
    }
}
