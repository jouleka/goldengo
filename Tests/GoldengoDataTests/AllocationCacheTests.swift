import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class AllocationCacheTests: XCTestCase {
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }
    /// GOL-95 v2: unpinned manual spends are wallet-cash and leave the allocator entirely, so
    /// mutation tests pin their spends to a source (bank-paid) to stay allocator-relevant.
    private func sourceID(_ store: IngestionStore, named name: String) async throws -> String? {
        try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
            .sources.first { $0.name == name }?.id
    }

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
        try await store.logManual(amount: 300, currency: .all, merchant: "Coffee", categoryName: nil,
                                  fundedBySourceID: try await sourceID(store, named: "Sister"))
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

    func test_allocation_recomputesWhenRateValuesChange_atSameAsOf() async throws {
        // Cross-currency ledger: a EUR source funding an ALL spend → the allocation output depends on
        // the EUR↔ALL rate VALUE. Two rate tables sharing asOf but differing in values must NOT collide
        // in the cache (regression guard: the fingerprint keys on the full table, not just asOf).
        let store = try makeStore()
        try await store.logIncome(amount: 5, currency: CurrencyCode("EUR"), sourceName: "Sis")
        try await store.logManual(amount: 1000, currency: .all, merchant: "Rent", categoryName: nil,
                                  fundedBySourceID: try await sourceID(store, named: "Sis"))
        let asOf = Date(timeIntervalSince1970: 1_780_000_000)
        // 5 EUR funds 500 ALL at rate A (→ 500 ALL unaccounted) but 1000 ALL at rate B (→ 0 unaccounted).
        let ratesA = RateTable(base: .all, rates: ["ALL": 1, "EUR": 0.01], asOf: asOf)   // 1 EUR = 100 ALL
        let ratesB = RateTable(base: .all, rates: ["ALL": 1, "EUR": 0.005], asOf: asOf)  // 1 EUR = 200 ALL

        let snapA = try await store.provenanceSnapshot(displayCurrency: .all, rates: ratesA)
        let countA = await store.allocationComputeCount
        let snapB = try await store.provenanceSnapshot(displayCurrency: .all, rates: ratesB)
        let countB = await store.allocationComputeCount

        XCTAssertGreaterThan(countB, countA, "Different rate values (same asOf) → recompute, not a stale hit.")
        XCTAssertNotEqual(snapA.unaccounted, snapB.unaccounted, "Recompute must reflect the new FX values.")
    }
}
