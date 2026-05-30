import Foundation
import SwiftData

@Model
public final class CategoryRecord {
    public var name: String = ""
    public var icon: String = "circle"
    public var colorHex: String = "#0A84FF"
    @Relationship(deleteRule: .nullify, inverse: \ExpenseRecord.category)
    public var expenses: [ExpenseRecord]? = []

    public init(name: String = "", icon: String = "circle", colorHex: String = "#0A84FF") {
        self.name = name; self.icon = icon; self.colorHex = colorHex
    }
}
