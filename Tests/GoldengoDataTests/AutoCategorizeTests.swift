import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class AutoCategorizeTests: XCTestCase {
    func test_ingest_appliesMerchantDefaultCategory() async throws {
        let container = try ModelContainer.goldengoInMemory()
        // Seed a merchant->category memory
        let seed = ModelContext(container)
        let groceries = CategoryRecord(name: "Groceries", icon: "cart", colorHex: "#34C759")
        let merchant = MerchantRecord(displayName: "Spar", normalizedName: "SPAR",
                                      defaultCategory: groceries)
        seed.insert(groceries); seed.insert(merchant); try seed.save()

        let store = IngestionStore(modelContainer: container)
        let tx = NormalizedTransaction(externalID: "z1", amount: 800, currency: .all,
            date: .now, rawMerchant: "SPAR 12", kind: .expense, accountRef: "cash")
        _ = try await store.ingest(tx, source: .imported)

        let snap = try await store.snapshot(dedupeKey: "ext:z1")
        XCTAssertEqual(snap?.categoryName, "Groceries")
    }
}
