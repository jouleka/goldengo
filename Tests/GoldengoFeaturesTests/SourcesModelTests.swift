import XCTest
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class SourcesModelTests: XCTestCase {
    func test_load_exposesSourceBalances() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logIncome(amount: 200, currency: .eur, sourceName: "Sister", date: .now)
        let model = SourcesModel(store: store, currency: .all)
        await model.load()
        XCTAssertEqual(model.snapshot?.sources.first?.name, "Sister")
        XCTAssertEqual(model.snapshot?.sources.first?.remaining, 200)
    }

    func test_addIncome_createsSource() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = SourcesModel(store: store, currency: .all)
        await model.addIncome(amount: 5000, currency: .all, sourceName: "Friday cash")
        await model.load()
        XCTAssertEqual(model.snapshot?.sources.count, 1)
        XCTAssertEqual(model.snapshot?.sources.first?.name, "Friday cash")
    }

    func test_addIncome_ignoresEmptyOrZero() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = SourcesModel(store: store, currency: .all)
        await model.addIncome(amount: 0, currency: .all, sourceName: "X")
        await model.addIncome(amount: 100, currency: .all, sourceName: "  ")
        await model.load()
        XCTAssertEqual(model.snapshot?.sources.count, 0)
    }
}
