import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class AllocationCacheTests: XCTestCase {
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    func test_allocation_reusedWhenNothingChanged() async throws {
        let store = try makeStore()
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister")
        try await store.logManual(amount: 200, currency: .all, merchant: "Coffee", categoryName: nil)
        _ = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let after1 = await store.allocationComputeCount
        _ = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let after2 = await store.allocationComputeCount
        XCTAssertEqual(after1, 1, "First snapshot is a cache miss → exactly one allocation.")
        XCTAssertEqual(after2, 1, "No mutation between calls → reuse the cache, not recompute.")
    }

    func test_allocation_recomputesAfterMutation_andReflectsIt() async throws {
        let store = try makeStore()
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister")
        _ = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let before = await store.allocationComputeCount
        try await store.logManual(amount: 300, currency: .all, merchant: "Coffee", categoryName: nil)
        let snap = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let after = await store.allocationComputeCount
        XCTAssertGreaterThan(after, before, "A new spend changes the fingerprint → recompute.")
        XCTAssertEqual(snap.sources.first { $0.name == "Sister" }?.remaining, 700, "Recompute reflects the spend.")
    }

    func test_allocation_recomputesOnCurrencyChange() async throws {
        let store = try makeStore()
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister")
        _ = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let a = await store.allocationComputeCount
        _ = try await store.provenanceSnapshot(displayCurrency: CurrencyCode("EUR"), rates: SeedRates.table)
        let b = await store.allocationComputeCount
        XCTAssertGreaterThan(b, a, "A different display currency is a different fingerprint → recompute.")
    }
}
