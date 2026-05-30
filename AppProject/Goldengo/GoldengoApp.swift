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
    }
    var body: some Scene {
        WindowGroup {
            QuickAddView(model: QuickAddModel(store: GoldengoStore.shared()))
        }
        .modelContainer(GoldengoStore.container)
    }
}
