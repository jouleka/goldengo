import Foundation
import SwiftData
import GoldengoData

/// Process-wide SwiftData container + ingestion store for the app and its intents.
@MainActor
public enum GoldengoStore {
    public static let container: ModelContainer = {
        try! ModelContainer(for: ModelContainer.goldengoSchema)   // on-disk; CloudKit wired in a later plan
    }()
    public static func shared() -> IngestionStore { IngestionStore(modelContainer: container) }
}
