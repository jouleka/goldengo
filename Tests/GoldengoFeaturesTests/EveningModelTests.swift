import XCTest
import SwiftData
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class EveningModelTests: XCTestCase {
    /// Log a daily coffee for the last `startDaysAgo` days, ending yesterday (none today).
    private func seedDailyCoffee(_ store: IngestionStore, startDaysAgo: Int = 7) async throws {
        for k in stride(from: startDaysAgo, through: 1, by: -1) {
            try await store.logManual(amount: 200, currency: .all, merchant: "Coffee",
                                      categoryName: nil, date: Date().addingTimeInterval(Double(-k) * 86_400))
        }
    }
    private func freshSummary() -> SharedSummary { SharedSummary(suiteName: "evening-\(UUID().uuidString)") }

    func test_load_surfacesTodaysIntention_ghosts_andTotal() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store)
        try await store.logManual(amount: 500, currency: .all, merchant: "Lunch", categoryName: nil, date: .now)
        let summary = freshSummary()
        summary.setIntention("be present", on: .now)

        let model = EveningModel(store: store, currency: .all, summary: summary)
        await model.load()

        XCTAssertEqual(model.intention, "be present")
        XCTAssertTrue(model.ghosts.contains { $0.displayName == "Coffee" })
        XCTAssertFalse(model.todayTotalText.isEmpty)
    }

    func test_load_intentionNil_whenSetOnAPriorDay() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let summary = freshSummary()
        summary.setIntention("old note", on: Date().addingTimeInterval(-2 * 86_400))
        let model = EveningModel(store: store, summary: summary)
        await model.load()
        XCTAssertNil(model.intention)
    }

    func test_confirm_logsTheUsual() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store)
        let model = EveningModel(store: store, summary: freshSummary())
        await model.load()
        let ghost = try XCTUnwrap(model.ghosts.first)
        let before = try await store.expenseCount()
        await model.confirm(ghost)
        let after = try await store.expenseCount()
        XCTAssertEqual(after, before + 1)
    }
}
