import Foundation
import SwiftData

public extension ModelContainer {
    // A computed property (not a stored `static let`) so it builds clean on every toolchain:
    // older Swift flags a non-Sendable stored static (`Schema` isn't `Sendable` there — the CI
    // failure), while newer Swift treats `Schema` as `Sendable`. No stored static = no shared
    // mutable state to police. Rebuilding the schema is cheap (only at container creation).
    static var goldengoSchema: Schema {
        Schema([
            ExpenseRecord.self, CategoryRecord.self, AccountRecord.self, MerchantRecord.self,
            ImportBatch.self, SubscriptionRecord.self, SourceRecord.self, WalletCount.self,
        ])
    }

    /// In-memory container for tests and previews (no CloudKit, no disk).
    static func goldengoInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: goldengoSchema, configurations: config)
    }
}
