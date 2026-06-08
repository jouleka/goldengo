import XCTest
import CoreGraphics
import GoldengoCore
import GoldengoData
@testable import GoldengoFeatures

@MainActor
final class ReceiptScanModelTests: XCTestCase {
    private func line(_ text: String, y: Double) -> RecognizedLine {
        RecognizedLine(text: text, boundingBox: CGRect(x: 0.1, y: y, width: 0.8, height: 0.03))
    }

    func test_populate_fillsDraftFromLines() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = ReceiptScanModel(store: store, currency: .all)
        model.populate(from: [line("SPAR TIRANA", y: 0.95),
                              line("30.05.2025", y: 0.88),
                              line("TOTALI 1.250 L", y: 0.2)])
        XCTAssertEqual(model.amountString, "1250")
        XCTAssertEqual(model.merchant, "SPAR TIRANA")
        XCTAssertNotNil(model.date)
        XCTAssertFalse(model.amountWasUnreadable)
    }

    func test_populate_flagsUnreadableAmount() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = ReceiptScanModel(store: store, currency: .all)
        model.populate(from: [line("THANK YOU", y: 0.2)])
        XCTAssertEqual(model.amountString, "")
        XCTAssertTrue(model.amountWasUnreadable)
        XCTAssertFalse(model.canSave)
    }

    func test_save_logsExpenseAsManual() async throws {
        let store = IngestionStore(modelContainer: try .goldengoInMemory())
        let model = ReceiptScanModel(store: store, currency: .all)
        model.populate(from: [line("Cafe Elida", y: 0.95), line("TOTALI 300", y: 0.2)])
        await model.save()
        let recents = try await store.recentExpenses(limit: 1)
        XCTAssertEqual(recents.first?.amount, 300)
        XCTAssertEqual(recents.first?.merchantName, "Cafe Elida")
        XCTAssertEqual(recents.first?.source, .manual)
    }
}
