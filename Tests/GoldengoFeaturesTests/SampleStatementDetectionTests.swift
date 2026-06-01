import XCTest
import SwiftData
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

final class SampleStatementDetectionTests: XCTestCase {
    /// End-to-end: importing the built-in demo sample must surface a monthly subscription
    /// (so "Try a sample statement" actually showcases GOL-7) while NOT flagging the salary credit.
    @MainActor
    func test_sampleStatement_yieldsMonthlyNetflix_andExcludesSalary() async throws {
        let store = IngestionStore(modelContainer: try ModelContainer.goldengoInMemory())
        let model = ImportModel(store: store)
        await model.importCSV(text: SampleStatement.csv, fileName: "sample.csv")

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        _ = try await store.refreshSubscriptions(now: now)
        let cands = try await store.subscriptionCandidates()

        let netflix = cands.first { $0.displayName.uppercased().contains("NETFLIX") }
        XCTAssertNotNil(netflix, "sample should surface a NETFLIX subscription")
        XCTAssertEqual(netflix?.cadence, .monthly)
        XCTAssertFalse(cands.contains { $0.displayName.uppercased().contains("SALARY") },
                       "income (SALARY) must not be detected as a subscription")
    }
}
