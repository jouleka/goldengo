import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

/// These live in GoldengoDataTests (not GoldengoIntentsTests) because they are async:
/// linking AppIntents into an xctest process breaks XCTest's async bridge — the runner
/// abandons the test mid-run (silent false green) and the orphaned task corrupts the
/// process (layout-dependent SIGSEGV; found 2026-07-02, Xcode 26.6). GoldengoIntentsTests
/// must stay sync-only.
final class ExpenseLoggingTests: XCTestCase {
    func test_logExpense_persistsThroughStore() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = try await ExpenseLogging.log(amount: 1500, currencyCode: "ALL",
                                                   merchant: nil, categoryName: "Groceries", store: store)
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1)
        XCTAssertTrue(summary.contains("1,500"))
    }

    func test_log_unknownMerchant_keepsMerchant_andCategorizesOther() async throws {
        // An auto-captured Apple Pay payment passes a merchant and no category. The merchant must be
        // kept (it labels the Recent row and feeds subscription detection) and an unrecognised merchant
        // must land in a real "Other" category — never silently uncategorized.
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = try await ExpenseLogging.log(amount: 350, currencyCode: "ALL",
                                                   merchant: "Tiny Cafe", categoryName: nil, store: store)
        let snap = try await store.recentExpenses().first
        XCTAssertEqual(snap?.merchantName, "Tiny Cafe")
        XCTAssertEqual(snap?.categoryName, "Other")
        XCTAssertTrue(summary.contains("350"))
    }

    func test_log_automaticTrue_recordsAutomaticSource() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await ExpenseLogging.log(amount: 1500, currencyCode: "ALL", merchant: "Spar",
                                         categoryName: nil, store: store, automatic: true)
        let recents = try await store.recentExpenses(limit: 5)
        XCTAssertEqual(recents.first?.source, .automatic)
    }

    func test_log_defaultStaysManual() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        _ = try await ExpenseLogging.log(amount: 1500, currencyCode: "ALL", merchant: "Spar",
                                         categoryName: nil, store: store)
        let recents = try await store.recentExpenses(limit: 5)
        XCTAssertEqual(recents.first?.source, .manual)
    }
}
