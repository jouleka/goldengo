import Foundation
import SwiftData
import GoldengoData

/// Process-wide SwiftData container + ingestion store for the app and its intents.
@MainActor
public enum GoldengoStore {
    public static let container: ModelContainer = {
        let config = ModelConfiguration(groupContainer: .identifier(SharedSummary.appGroupID))
        return (try? ModelContainer(for: ModelContainer.goldengoSchema, configurations: config))
            ?? (try! ModelContainer(for: ModelContainer.goldengoSchema))   // fallback if entitlement missing in a context
    }()
    public static func shared() -> IngestionStore { IngestionStore(modelContainer: container) }
}
