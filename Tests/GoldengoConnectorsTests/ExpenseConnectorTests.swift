import XCTest
import GoldengoCore
@testable import GoldengoConnectors

private struct FakeConnector: ExpenseConnector {
    let id = "fake"
    let capabilities = ConnectorCapabilities(supportsBackfill: true, supportsRealtime: false, supportsBalances: false)
    func pull(since checkpoint: SyncCheckpoint?) async throws -> [NormalizedTransaction] {
        [NormalizedTransaction(externalID: "1", amount: 500, currency: .all,
                               date: .now, rawMerchant: "Spar", kind: .expense, accountRef: "cash")]
    }
}

final class ExpenseConnectorTests: XCTestCase {
    func test_connector_pullsNormalizedTransactions() async throws {
        let c = FakeConnector()
        let txns = try await c.pull(since: nil)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.dedupeKey, "ext:1")
        XCTAssertTrue(c.capabilities.supportsBackfill)
    }
}
