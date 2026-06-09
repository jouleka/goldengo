import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class SourcePinningTests: XCTestCase {
    private func makeStore() throws -> IngestionStore { IngestionStore(modelContainer: try .goldengoInMemory()) }

    /// Pin an expense to a source via updateExpense → the funding label follows the pin, not FIFO.
    func test_pinViaUpdateExpense_overridesFundingLabel() async throws {
        let store = try makeStore()
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister",
                                  date: Date().addingTimeInterval(-2 * 86_400))
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Freelance",
                                  date: Date().addingTimeInterval(-86_400))
        try await store.logManual(amount: 300, currency: .all, merchant: "Rent", categoryName: nil)

        // FIFO baseline: oldest source (Sister) funds it.
        var rows = try await store.recentExpenses(limit: 10)
        var rent = try XCTUnwrap(rows.first { $0.merchantName == "Rent" })
        XCTAssertEqual(rent.fundedBy, "Sister")

        // Pin to Freelance → label follows the pin.
        let homeSources = try await store.homeData(rates: SeedRates.table).sources
        let freelanceID = try XCTUnwrap(homeSources.first { $0.name == "Freelance" }?.id)
        try await store.updateExpense(dedupeKey: rent.dedupeKey, amount: rent.amount, currency: nil,
                                      merchant: rent.merchantName, note: nil, categoryName: nil,
                                      date: rent.date, fundedBySourceID: freelanceID)
        rows = try await store.recentExpenses(limit: 10)
        rent = try XCTUnwrap(rows.first { $0.merchantName == "Rent" })
        XCTAssertEqual(rent.fundedBy, "Freelance")
        XCTAssertEqual(rent.fundedBySourceID, freelanceID, "Snapshot must carry the pin for the edit sheet.")

        // Clear the pin (back to Automatic) → FIFO again.
        try await store.updateExpense(dedupeKey: rent.dedupeKey, amount: rent.amount, currency: nil,
                                      merchant: rent.merchantName, note: nil, categoryName: nil,
                                      date: rent.date, fundedBySourceID: nil)
        rows = try await store.recentExpenses(limit: 10)
        rent = try XCTUnwrap(rows.first { $0.merchantName == "Rent" })
        XCTAssertEqual(rent.fundedBy, "Sister")
        XCTAssertNil(rent.fundedBySourceID)
    }

    /// A pin edit must invalidate the cached allocation (the fingerprint includes the pin).
    func test_pinChange_invalidatesAllocationCache() async throws {
        let store = try makeStore()
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister")
        try await store.logManual(amount: 300, currency: .all, merchant: "Rent", categoryName: nil)
        _ = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let before = await store.allocationComputeCount

        let rows = try await store.recentExpenses(limit: 10)
        let row = try XCTUnwrap(rows.first { $0.merchantName == "Rent" })
        let cacheSources = try await store.homeData(rates: SeedRates.table).sources
        let sisterID = try XCTUnwrap(cacheSources.first { $0.name == "Sister" }?.id)
        try await store.updateExpense(dedupeKey: row.dedupeKey, amount: row.amount, currency: nil,
                                      merchant: row.merchantName, note: nil, categoryName: nil,
                                      date: row.date, fundedBySourceID: sisterID)
        _ = try await store.provenanceSnapshot(displayCurrency: .all, rates: SeedRates.table)
        let after = await store.allocationComputeCount
        XCTAssertGreaterThan(after, before, "A pin edit changes the fingerprint → recompute.")
    }

    /// homeData carries the source options (for the edit sheet's Paid-from chips) and label colors.
    func test_homeData_carriesSourceOptions_andChipColor() async throws {
        let store = try makeStore()
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister")
        try await store.logManual(amount: 300, currency: .all, merchant: "Rent", categoryName: nil)
        let data = try await store.homeData(rates: SeedRates.table)
        let sister = try XCTUnwrap(data.sources.first { $0.name == "Sister" })
        let rent = try XCTUnwrap(data.rows.first { $0.merchantName == "Rent" })
        XCTAssertEqual(rent.fundedBy, "Sister")
        XCTAssertEqual(rent.fundedByColorIndex, sister.colorIndex,
                       "The chip's color index must match the funding source's palette slot.")
    }
}
