import Foundation
import SwiftData

@Model
public final class GoalRecord {
    public var id: String = ""
    public var name: String = ""
    public var targetAmount: Decimal = 0
    public var savedAmount: Decimal = 0
    public var currencyCode: String = "ALL"
    public var dueDate: Date?
    public var icon: String = "target"
    public var colorHex: String = "#D9A933"
    public var createdAt: Date = Date.now
    public var isArchived: Bool = false

    public init(id: String = UUID().uuidString, name: String = "", targetAmount: Decimal = 0,
                savedAmount: Decimal = 0, currencyCode: String = "ALL", dueDate: Date? = nil,
                icon: String = "target", colorHex: String = "#D9A933") {
        self.id = id; self.name = name; self.targetAmount = targetAmount
        self.savedAmount = savedAmount; self.currencyCode = currencyCode; self.dueDate = dueDate
        self.icon = icon; self.colorHex = colorHex
    }
}
