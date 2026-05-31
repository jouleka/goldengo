import XCTest
import SwiftData
@testable import GoldengoData

final class ImportBatchTests: XCTestCase {
    func test_importBatch_persists() throws {
        let container = try ModelContainer.goldengoInMemory()
        let ctx = ModelContext(container)
        ctx.insert(ImportBatch(fileName: "may.csv", rowCount: 10, importedCount: 8, dedupedCount: 2))
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<ImportBatch>())
        XCTAssertEqual(all.first?.fileName, "may.csv")
        XCTAssertEqual(all.first?.importedCount, 8)
    }
}
