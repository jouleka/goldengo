import Foundation
import SwiftData

/// A category allocation inside one purchase. The parent expense remains the bank/wallet truth;
/// splits only change how that total is understood in reports.
@Model
public final class ExpenseSplitRecord {
    public var id: String = ""
    public var amount: Decimal = 0
    public var categoryName: String = "Other"
    public var createdAt: Date = Date.now
    public var expense: ExpenseRecord?

    public init(id: String = UUID().uuidString, amount: Decimal = 0,
                categoryName: String = "Other", createdAt: Date = .now) {
        self.id = id; self.amount = amount; self.categoryName = categoryName; self.createdAt = createdAt
    }
}
