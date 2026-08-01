import Foundation
import Observation
import CoreGraphics
import GoldengoCore
import GoldengoData

public struct ReceiptItemDraft: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var amountString: String
    public var categoryName: String

    public init(id: String = UUID().uuidString, name: String, amount: Decimal,
                categoryName: String = "Other") {
        self.id = id; self.name = name
        self.amountString = NSDecimalNumber(decimal: amount).stringValue
        self.categoryName = categoryName
    }

    public var amount: Decimal { Decimal(string: amountString) ?? 0 }
}

@MainActor
@Observable
public final class ReceiptScanModel {
    public let store: IngestionStore
    public var currency: CurrencyCode
    public var amountString: String = ""
    public var merchant: String = ""
    public var selectedCategory: String?
    public var date: Date?
    public var items: [ReceiptItemDraft] = []
    public var useItemSplits = false
    public private(set) var savedCount: Int = 0
    public var errorText: String?
    /// True after a scan whose OCR yielded no usable total (drives the "enter it" hint in the review).
    public private(set) var amountWasUnreadable = false

    public init(store: IngestionStore, currency: CurrencyCode = .all) {
        self.store = store
        self.currency = currency
    }

    public var amountDecimal: Decimal { Decimal(string: amountString) ?? 0 }
    public var itemTotal: Decimal { items.reduce(Decimal.zero) { $0 + $1.amount } }
    public var itemRemainder: Decimal { max(0, amountDecimal - itemTotal) }
    public var itemSplitsAreValid: Bool {
        !useItemSplits || (items.count >= 2 && items.allSatisfy {
            $0.amount > 0 && !$0.categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } && itemTotal <= amountDecimal)
    }
    public var canSave: Bool { amountDecimal > 0 && itemSplitsAreValid }

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
        items = parsed.items.map {
            ReceiptItemDraft(id: $0.id, name: $0.name, amount: $0.amount,
                             categoryName: suggestedCategory(for: $0.name))
        }
        useItemSplits = items.count >= 2
    }

    @discardableResult
    public func save() async -> Bool {
        guard canSave else { return false }
        do {
            try await store.logManual(amount: amountDecimal, currency: currency,
                                      merchant: merchant.isEmpty ? nil : merchant,
                                      categoryName: selectedCategory,
                                      date: date ?? .now,
                                      splits: receiptSplits)
            savedCount += 1
            errorText = nil
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    public func addItem() {
        items.append(ReceiptItemDraft(name: "Item", amount: max(0, itemRemainder),
                                      categoryName: selectedCategory ?? "Other"))
        useItemSplits = true
    }

    public func removeItem(id: String) { items.removeAll { $0.id == id } }

    private var receiptSplits: [TransactionSplit] {
        guard useItemSplits, itemSplitsAreValid else { return [] }
        var totals: [String: Decimal] = [:]
        for item in items { totals[item.categoryName, default: 0] += item.amount }
        if itemRemainder > 0 { totals[selectedCategory ?? "Other", default: 0] += itemRemainder }
        guard totals.count > 1 else { return [] }
        return totals.keys.sorted().map { TransactionSplit(amount: totals[$0] ?? 0, categoryName: $0) }
    }

    private func suggestedCategory(for raw: String) -> String {
        let text = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let rules: [(String, [String])] = [
            ("Groceries", ["milk", "bread", "cheese", "meat", "fruit", "water", "food", "rice", "pasta", "egg"]),
            ("Personal care", ["shampoo", "soap", "tooth", "deodorant", "razor", "cosmetic"]),
            ("Pharmacy", ["medicine", "tablet", "vitamin", "pharmacy", "medical"]),
            ("Alcohol", ["beer", "wine", "vodka", "whisky", "alcohol"]),
            ("Household", ["detergent", "cleaner", "tissue", "kitchen", "battery", "bulb"]),
        ]
        return rules.first(where: { $0.1.contains(where: text.contains) })?.0 ?? "Other"
    }
}

extension ReceiptScanModel: Identifiable {
    public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
