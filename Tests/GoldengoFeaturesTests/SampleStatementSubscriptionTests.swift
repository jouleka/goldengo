import XCTest
import GoldengoCore
import GoldengoData
import GoldengoImport
@testable import GoldengoFeatures

/// Localizes the "imported the sample but no subscription shows" report: does the real
/// import → refreshSubscriptions → candidates path actually detect the sample's 3 monthly NETFLIX
/// charges? If this passes, the missing subscription is a UI-refresh problem, not detection.
final class SampleStatementSubscriptionTests: XCTestCase {
    @MainActor
    func test_sampleImport_surfacesNetflixMonthlySubscription() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let txns = StatementImporter.transactions(fromCSV: SampleStatement.csv, currency: .all)
        XCTAssertFalse(txns.isEmpty, "sample CSV should parse into transactions")
        _ = try await store.importStatement(txns, fileName: "sample.csv")

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let detectedCount = try await store.refreshSubscriptions(now: now)
        let candidates = try await store.subscriptionCandidates()

        XCTAssertGreaterThan(detectedCount, 0, "expected at least one detected subscription from the sample")
        XCTAssertTrue(candidates.contains { $0.displayName.uppercased().contains("NETFLIX") },
                      "NETFLIX (3 monthly charges) should be detected — got: \(candidates.map(\.displayName))")
    }
}
