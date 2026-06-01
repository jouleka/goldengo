import SwiftUI
import SwiftData
import GoldengoData
import GoldengoFeatures
import GoldengoIntents

@main
struct GoldengoApp: App {
    init() {
        // Wire the App Intent's store provider to the app's shared container.
        IntentEnvironment.storeProvider = { GoldengoStore.shared() }

        #if DEBUG
        // QA affordance (DEBUG only, off by default): launch with the env var
        // GOLDENGO_SEED_SAMPLE=1 to import the demo statement on startup, so the UI can be
        // populated for screenshots / UI verification without driving the file picker.
        if ProcessInfo.processInfo.environment["GOLDENGO_SEED_SAMPLE"] == "1" {
            Task { @MainActor in
                await ImportModel(store: GoldengoStore.shared())
                    .importCSV(text: SampleStatement.csv, fileName: "sample.csv")
            }
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            RootView(store: GoldengoStore.shared())
        }
        .modelContainer(GoldengoStore.container)
    }
}
