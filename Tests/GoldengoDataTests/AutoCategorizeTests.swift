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

    func test_merge_backfillsMerchantCategory_learnedAfterManualEntry() async throws {
        let container = try ModelContainer.goldengoInMemory()
        let store = IngestionStore(modelContainer: container)
        let tx = NormalizedTransaction(externalID: nil, amount: 800, currency: .all,
            date: Date(timeIntervalSince1970: 1_750_000_000), rawMerchant: "SPAR 12",
            kind: .expense, accountRef: "cash")
        // 1) Manual entry before any merchant memory exists -> no category.
        _ = try await store.ingest(tx, source: .manual)
        let before = try await store.snapshot(dedupeKey: tx.dedupeKey)
        XCTAssertNil(before?.categoryName)
        // 2) Learn the merchant -> category mapping.
        let seed = ModelContext(container)
        let groceries = CategoryRecord(name: "Groceries", icon: "cart", colorHex: "#34C759")
        seed.insert(groceries)
        seed.insert(MerchantRecord(displayName: "Spar", normalizedName: "SPAR", defaultCategory: groceries))
        try seed.save()
        // 3) Import with the same dedupeKey merges and back-fills the category.
        _ = try await store.ingest(tx, source: .imported)
        let after = try await store.snapshot(dedupeKey: tx.dedupeKey)
        XCTAssertEqual(after?.categoryName, "Groceries")
        let count = try await store.expenseCount()
        XCTAssertEqual(count, 1)
    }
}
