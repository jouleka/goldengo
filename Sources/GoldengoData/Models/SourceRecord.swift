import Foundation
import SwiftData

/// A named money origin ("Sister", "Freelance", "Friday cash"). Income records link to it;
/// expenses draw from sources via the pure FIFO allocator (never stored).
@Model
public final class SourceRecord {
    public var id: String = ""                 // stable UUID string — the allocator's sourceID (rename-safe)
    public var name: String = ""
    public var currencyCode: String = "ALL"    // the source's native currency
    public var colorIndex: Int = 0             // palette slot for the distinct color
    public var createdAt: Date = Date.now
    public var isArchived: Bool = false        // soft-delete tombstone (CloudKit-friendly)
    // Inverse of ExpenseRecord.provenanceSource. REQUIRED for CloudKit (cf. AccountRecord).
    @Relationship(deleteRule: .nullify, inverse: \ExpenseRecord.provenanceSource)
    public var incomes: [ExpenseRecord]? = []

    public init(id: String = UUID().uuidString, name: String = "", currencyCode: String = "ALL",
                colorIndex: Int = 0, createdAt: Date = .now, isArchived: Bool = false) {
        self.id = id; self.name = name; self.currencyCode = currencyCode
        self.colorIndex = colorIndex; self.createdAt = createdAt; self.isArchived = isArchived
    }
}
