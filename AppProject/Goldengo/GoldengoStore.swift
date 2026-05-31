import Foundation
import SwiftData
import GoldengoData

/// Process-wide SwiftData container + ingestion store for the app and its intents.
@MainActor
public enum GoldengoStore {
    /// CloudKit container id. Sync only activates once the iCloud capability + this container
    /// are provisioned in Xcode under your Apple Developer team (see README "iCloud / CloudKit").
    public static let cloudContainerID = "iCloud.com.goldengo.app"

    public static let container: ModelContainer = {
        let schema = ModelContainer.goldengoSchema
        let group: ModelConfiguration.GroupContainer = .identifier(SharedSummary.appGroupID)

        // 1) Preferred: App Group store synced via the CloudKit private database. Requires the
        //    iCloud entitlement + a provisioned container + the user signed into iCloud. If any
        //    of that is missing it throws here and we fall back to a local store — same data,
        //    no sync — so an unprovisioned build (e.g. the simulator) still runs.
        let cloudConfig = ModelConfiguration(groupContainer: group,
                                             cloudKitDatabase: .private(cloudContainerID))
        if let c = try? ModelContainer(for: schema, configurations: cloudConfig) { return c }

        // 2) Local App Group store (shared with the widget). This MUST work — fail loudly in dev
        //    so a broken App Group entitlement surfaces immediately rather than silently desyncing.
        let localConfig = ModelConfiguration(groupContainer: group)
        do {
            return try ModelContainer(for: schema, configurations: localConfig)
        } catch {
            #if DEBUG
            fatalError("App Group container failed — check the '\(SharedSummary.appGroupID)' entitlement: \(error)")
            #else
            return try! ModelContainer(for: schema)
            #endif
        }
    }()

    public static func shared() -> IngestionStore { IngestionStore(modelContainer: container) }
}
