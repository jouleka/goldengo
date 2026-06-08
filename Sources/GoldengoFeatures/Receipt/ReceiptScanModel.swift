import Foundation
import Observation
import CoreGraphics
import GoldengoCore
import GoldengoData

@MainActor
@Observable
public final class ReceiptScanModel {
    public let store: IngestionStore
    public var currency: CurrencyCode
    public var amountString: String = ""
    public var merchant: String = ""
    public var selectedCategory: String?
    public var date: Date?
    public private(set) var savedCount: Int = 0
    public var errorText: String?
    /// True after a scan whose OCR yielded no usable total (drives the "enter it" hint in the review).
    public private(set) var amountWasUnreadable = false

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store
        self.currency = currency
    }

    public var amountDecimal: Decimal { Decimal(string: amountString) ?? 0 }
    public var canSave: Bool { amountDecimal > 0 }

    /// Run OCR on a scanned page image (off the main actor), then fill the draft.
    public func handle(cgImage: CGImage) async {
        let lines = (try? await Task.detached { try ReceiptOCR.recognizeLines(in: cgImage) }.value) ?? []
        populate(from: lines)
    }

    /// Pure draft population from recognized lines (unit-tested without a camera).
    public func populate(from lines: [RecognizedLine]) {
        let parsed = ReceiptParser.parse(lines, currency: currency)
        if let amount = parsed.amount {
            amountString = NSDecimalNumber(decimal: amount).stringValue
            amountWasUnreadable = false
        } else {
            amountString = ""
            amountWasUnreadable = true
        }
        merchant = parsed.merchant ?? ""
        date = parsed.date
        selectedCategory = nil
    }

    public func save() async {
        guard canSave else { return }
        do {
            try await store.logManual(amount: amountDecimal, currency: currency,
                                      merchant: merchant.isEmpty ? nil : merchant,
                                      categoryName: selectedCategory,
                                      date: date ?? .now)
            savedCount += 1
        } catch {
            errorText = error.localizedDescription
        }
    }
}

extension ReceiptScanModel: Identifiable {
    public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
