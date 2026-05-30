import Foundation
import SwiftData
import GoldengoData

/// Process-wide SwiftData container + ingestion store for the app and its intents.
@MainActor
public enum GoldengoStore {
    public static let container: ModelContainer = {
        let config = ModelConfiguration(groupContainer: .identifier(SharedSummary.appGroupID))
        do {
            return try ModelContainer(for: ModelContainer.goldengoSchema, configurations: config)
        } catch {
            // Fail loudly in development so a missing App Group entitlement surfaces here
            // (a silent local-container fallback would desync the app and the widget).
            #if DEBUG
            fatalError("App Group container failed — check the '\(SharedSummary.appGroupID)' entitlement: \(error)")
            #else
            return try! ModelContainer(for: ModelContainer.goldengoSchema)
            #endif
        }
    }()
    public static func shared() -> IngestionStore { IngestionStore(modelContainer: container) }
}
