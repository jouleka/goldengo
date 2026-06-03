import SwiftUI
import SwiftData
import GoldengoData
import GoldengoFeatures
import GoldengoIntents

@main
struct GoldengoApp: App {
    init() {
        #if DEBUG
        // QA affordance (DEBUG only, off by default): launch with the env var
        // GOLDENGO_SEED_SAMPLE=1 to import the demo statement on startup, so the UI can be
        // populated for screenshots / UI verification without driving the file picker.
        if ProcessInfo.processInfo.environment["GOLDENGO_SEED_SAMPLE"] == "1" {
            Task { @MainActor in
                let store = GoldengoStore.shared()
                await ImportModel(store: store).importCSV(text: SampleStatement.csv, fileName: "sample.csv")
                // Confirm the detected subscription so the demo shows the full feature: a confirmed
                // subscription plus its auto-linked charges (the "repeat" badge in Recent).
                _ = try? await store.refreshSubscriptions()
                if let sub = (try? await store.subscriptionCandidates())?.first {
                    try? await store.confirmSubscription(matchKey: sub.id)
                }
                // The sample charges are dated Mar–May, so "this month" on Home would be 0.
                // Log one current-dated expense so the dashboard's month total + categories
                // are non-zero for screenshots.
                _ = try? await store.logManual(amount: 850, currency: .all, merchant: "Demo Lunch", categoryName: "Food")
            }
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            RootView(store: GoldengoStore.shared())
                .task { await GoldengoStore.refreshExchangeRates() }
        }
        .modelContainer(GoldengoStore.container)
    }
}
