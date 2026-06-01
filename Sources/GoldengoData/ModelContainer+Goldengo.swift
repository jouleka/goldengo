import Foundation
import SwiftData

public extension ModelContainer {
    static let goldengoSchema = Schema([
        ExpenseRecord.self, CategoryRecord.self, AccountRecord.self, MerchantRecord.self,
        ImportBatch.self, SubscriptionRecord.self,
    ])

    /// In-memory container for tests and previews (no CloudKit, no disk).
    static func goldengoInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: goldengoSchema, configurations: config)
    }
}
