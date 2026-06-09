import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class RhythmGhostTests: XCTestCase {
    /// Log a daily coffee for `startDaysAgo` consecutive days ending yesterday (none today).
    private func seedDailyCoffee(_ store: IngestionStore, startDaysAgo: Int = 7) async throws {
        for k in stride(from: startDaysAgo, through: 1, by: -1) {
            try await store.logManual(amount: 200, currency: .all, merchant: "Coffee",
                                      categoryName: nil, date: Date().addingTimeInterval(Double(-k) * 86_400))
        }
    }

    func test_rhythmGhosts_surfacesDailyPattern() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store)
        let ghosts = try await store.rhythmGhosts()
        XCTAssertEqual(ghosts.first?.displayName, "Coffee")
        XCTAssertEqual(ghosts.first?.amount, 200)
    }

    func test_rhythmGhosts_excludesAlreadyLoggedToday() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store)
        try await store.logManual(amount: 200, currency: .all, merchant: "Coffee", categoryName: nil, date: .now)
        let ghosts = try await store.rhythmGhosts()
        XCTAssertFalse(ghosts.contains { $0.normalizedMerchant == "COFFEE" },
                       "Already logged today → no ghost (no double-count).")
    }

    func test_confirmRhythmGhost_logsExpenseAtAmountToday() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store)
        let before = try await store.expenseCount()
        let ghosts = try await store.rhythmGhosts()
        let ghost = try XCTUnwrap(ghosts.first)
        try await store.confirmRhythmGhost(ghost, amount: ghost.amount)
        let after = try await store.expenseCount()
        XCTAssertEqual(after, before + 1)
        let recent = try await store.recentExpenses(limit: 1).first
        XCTAssertEqual(recent?.merchantName, "Coffee")
        XCTAssertEqual(recent?.amount, 200)
        XCTAssertEqual(recent?.source, .manual)
    }
}
