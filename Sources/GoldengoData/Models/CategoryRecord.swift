import Foundation
import SwiftData

@Model
public final class CategoryRecord {
    public var name: String = ""
    public var icon: String = "circle"
    public var colorHex: String = "#0A84FF"
    /// Recurring monthly cap in the user's display currency. nil = no cap.
    public var monthlyBudget: Decimal?
    /// Notify-once dedupe: the highest level we've PUSHED for `budgetAlertMonth`.
    public var budgetAlertLevelRaw: String = "none"
    /// The start-of-month `budgetAlertLevelRaw` applies to. nil = never pushed.
    public var budgetAlertMonth: Date?
    @Relationship(deleteRule: .nullify, inverse: \ExpenseRecord.category)
    public var expenses: [ExpenseRecord]? = []
    // Inverse of MerchantRecord.defaultCategory. REQUIRED for CloudKit (every relationship needs an
    // inverse) — without it the SwiftData+CloudKit store fails to load and the app crashes on launch.
    @Relationship(deleteRule: .nullify, inverse: \MerchantRecord.defaultCategory)
    public var merchants: [MerchantRecord]? = []

    public init(name: String = "", icon: String = "circle", colorHex: String = "#0A84FF") {
        self.name = name; self.icon = icon; self.colorHex = colorHex
    }
}
