import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class RhythmGhostModelTests: XCTestCase {
    private func seedDailyCoffee(_ store: IngestionStore) async throws {
        for k in stride(from: 7, through: 1, by: -1) {
            try await store.logManual(amount: 200, currency: .all, merchant: "Coffee",
                                      categoryName: nil, date: Date().addingTimeInterval(Double(-k) * 86_400))
        }
    }

    func test_load_populatesGhosts() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store)
        let model = RecentExpensesModel(store: store, currency: .all)
        await model.load()
        XCTAssertEqual(model.ghosts.first?.displayName, "Coffee")
    }

    func test_confirm_logsAndClearsGhost() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await seedDailyCoffee(store)
        let model = RecentExpensesModel(store: store, currency: .all)
        await model.load()
        let ghost = try XCTUnwrap(model.ghosts.first)
        await model.confirm(ghost)
        XCTAssertFalse(model.ghosts.contains { $0.normalizedMerchant == ghost.normalizedMerchant },
                       "Confirmed → logged today → ghost gone on reload.")
    }
}
