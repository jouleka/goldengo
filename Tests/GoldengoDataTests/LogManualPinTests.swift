import XCTest
import SwiftData
import GoldengoCore
@testable import GoldengoData

final class LogManualPinTests: XCTestCase {
    /// logManual with a fundedBySourceID pins the expense at creation → its funding label follows the
    /// pin, not FIFO (GOL-90: choosing the source at add time).
    func test_logManual_withPin_fundsFromChosenSource() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        // Two sources; FIFO would pick the older (Sister).
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister",
                                  date: Date().addingTimeInterval(-2 * 86_400))
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Freelance",
                                  date: Date().addingTimeInterval(-86_400))
        let snapshot = try await store.provenanceSnapshot(displayCurrency: .all)
        let freelanceID = try XCTUnwrap(snapshot.sources.first { $0.name == "Freelance" }?.id)

        _ = try await store.logManual(amount: 300, currency: .all, merchant: "Rent",
                                      categoryName: nil, fundedBySourceID: freelanceID)

        let rows = try await store.recentExpenses(limit: 10)
        let rent = try XCTUnwrap(rows.first { $0.merchantName == "Rent" })
        XCTAssertEqual(rent.fundedBy, "Freelance", "The chosen source funds it, overriding FIFO.")
        XCTAssertEqual(rent.fundedBySourceID, freelanceID)
    }

    /// GOL-95 v2: logManual without a pin is CASH by default — it drains the wallet, never a
    /// bank-side pool, and the chip says so. (Replaces the v1 automatic-FIFO rule.)
    func test_logManual_withoutPin_isWalletCash() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Sister",
                                  date: Date().addingTimeInterval(-2 * 86_400))
        try await store.logIncome(amount: 1000, currency: .all, sourceName: "Freelance",
                                  date: Date().addingTimeInterval(-86_400))
        _ = try await store.logManual(amount: 300, currency: .all, merchant: "Rent", categoryName: nil)
        let rows = try await store.recentExpenses(limit: 10)
        let rent = try XCTUnwrap(rows.first { $0.merchantName == "Rent" })
        XCTAssertEqual(rent.fundedBy, "Wallet")
        XCTAssertNil(rent.fundedBySourceID)
        let snapshot = try await store.provenanceSnapshot(displayCurrency: .all)
        XCTAssertEqual(snapshot.sources.first { $0.name == "Sister" }?.remaining, 1000,
                       "A cash spend never drains the bank-side pools")
    }
}
