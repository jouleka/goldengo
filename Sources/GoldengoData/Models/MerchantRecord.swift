import Foundation
import SwiftData

@Model
public final class MerchantRecord {
    public var displayName: String = ""
    public var normalizedName: String = ""
    public var useCount: Int = 0
    public var lastUsed: Date = Date.now
    public var defaultCategory: CategoryRecord?

    public init(displayName: String = "", normalizedName: String = "",
                useCount: Int = 0, lastUsed: Date = .now,
                defaultCategory: CategoryRecord? = nil) {
        self.displayName = displayName; self.normalizedName = normalizedName
        self.useCount = useCount; self.lastUsed = lastUsed
        self.defaultCategory = defaultCategory
    }
}
