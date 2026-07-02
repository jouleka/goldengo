import Foundation
import SwiftData

/// A person who owes the user money ("Owed to you"). Lent/repayment events link to it;
/// the balance is always DERIVED from the events (never stored) — same philosophy as the
/// provenance allocator: the records are the truth, balances are views.
@Model
public final class LoanRecord {
    public var id: String = ""                 // stable UUID string (rename-safe)
    public var personName: String = ""
    public var currencyCode: String = "ALL"    // the loan's native currency
    public var colorIndex: Int = 0             // palette slot (shared 8-color palette)
    public var createdAt: Date = Date.now
    public var isArchived: Bool = false        // soft-delete tombstone (CloudKit-friendly)
    // Inverse of ExpenseRecord.loan. REQUIRED for CloudKit (cf. SourceRecord).
    @Relationship(deleteRule: .nullify, inverse: \ExpenseRecord.loan)
    public var events: [ExpenseRecord]? = []

    public init(id: String = UUID().uuidString, personName: String = "", currencyCode: String = "ALL",
                colorIndex: Int = 0, createdAt: Date = .now, isArchived: Bool = false) {
        self.id = id; self.personName = personName; self.currencyCode = currencyCode
        self.colorIndex = colorIndex; self.createdAt = createdAt; self.isArchived = isArchived
    }
}
