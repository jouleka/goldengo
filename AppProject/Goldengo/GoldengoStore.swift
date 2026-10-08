import Foundation
import SwiftData
import GoldengoData

/// Process-wide SwiftData container + ingestion store for the app and its intents.
@MainActor
public enum GoldengoStore {
    public enum StorageMode {
        case cloud, sharedLocal, deviceLocal
        public var title: String {
            switch self {
            case .cloud: return "iCloud private sync"
            case .sharedLocal: return "This device + widget"
            case .deviceLocal: return "This device only"
            }
        }
    }
    /// CloudKit container id. Sync only activates once the iCloud capability + this container
    /// are provisioned in Xcode under your Apple Developer team (see README "iCloud / CloudKit").
    public static let cloudContainerID = "iCloud.com.goldengo.app"

    private static let setup: (container: ModelContainer, mode: StorageMode) = {
        let schema = ModelContainer.goldengoSchema
        let group: ModelConfiguration.GroupContainer = .identifier(SharedSummary.appGroupID)

        // 1) Preferred: App Group store synced via the CloudKit private database. Requires the
        //    iCloud entitlement + a provisioned container + the user signed into iCloud. If any
        //    of that is missing it throws here and we fall back — so an unprovisioned build runs.
        // ModelConfiguration traps before ModelContainer can throw if an explicitly named
        // App Group is inaccessible. Check it first so the local fallback is reachable.
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedSummary.appGroupID) != nil {
            let cloudConfig = ModelConfiguration(groupContainer: group,
                                                 cloudKitDatabase: .private(cloudContainerID))
            if let c = try? ModelContainer(for: schema, configurations: cloudConfig) { return (c, .cloud) }

            // 2) Local App Group store (shared with the widget), explicitly without CloudKit.
            let localGroupConfig = ModelConfiguration(groupContainer: group, cloudKitDatabase: .none)
            if let c = try? ModelContainer(for: schema, configurations: localGroupConfig) { return (c, .sharedLocal) }
        }

        // 3) Last resort: a plain local store in the app's own container (no App Group → the widget
        //    can't share this data). Keeps the app launchable everywhere. Reaching here on a real
        //    device means the App Group entitlement is broken — surface it loudly, but never make
        //    the app unlaunchable just because of an environment/provisioning quirk.
        #if DEBUG
        print("⚠️ Goldengo: App Group '\(SharedSummary.appGroupID)' unavailable — using a local-only store " +
              "(no widget data sharing). Expected in the Simulator; on device, check the App Group entitlement.")
        #endif
        let deviceConfig = ModelConfiguration(cloudKitDatabase: .none)
        return (try! ModelContainer(for: schema, configurations: deviceConfig), .deviceLocal)
    }()
    public static var container: ModelContainer { setup.container }
    public static var storageMode: StorageMode { setup.mode }

    public static func shared() -> IngestionStore { IngestionStore(modelContainer: container) }

    /// Refresh the exchange-rate cache on launch (no-op if the cache is still fresh). Offline-safe.
    public static func refreshExchangeRates() async {
        await ExchangeRateService().refreshIfNeeded()
    }
}
