import SwiftUI
import SwiftData
import GoldengoCore
import GoldengoData
import GoldengoFeatures
import GoldengoIntents
import UserNotifications

/// Handles the owed-to-you nudge's action buttons. "Remind me in a month" queues a fresh
/// nudge straight from the notification (no app open needed); "Log the payback…" and a plain
/// tap land on the Wallet tab so the payback is logged honestly (the amount is the user's
/// call — a repayment is never fabricated from a button).
final class GoldengoNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = GoldengoNotificationDelegate()

    // Reminders should surface even while the app is frontmost (a quiet banner).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        guard request.identifier.hasPrefix(LoanNudge.notificationPrefix) else {
            completionHandler(); return
        }
        switch response.actionIdentifier {
        case LoanNudge.remindAgainActionID:
            // One fresh nudge a month from NOW (09:00). The app's next re-sync replaces it
            // with the regular grid — either way, another reminder is guaranteed.
            if let content = request.content.mutableCopy() as? UNMutableNotificationContent {
                var comps = Calendar.current.dateComponents(
                    [.year, .month, .day], from: Date(timeIntervalSinceNow: 30 * 86_400))
                comps.hour = 9; comps.minute = 0
                center.add(UNNotificationRequest(
                    identifier: LoanNudge.notificationPrefix + "again:" + UUID().uuidString,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        default:
            // Body tap or "Log the payback…" (foreground action): stage the Wallet tab —
            // RootView routes there on activation via the pendingTab handoff.
            SharedSummary().setPendingTab(5)
        }
        completionHandler()
    }
}

@main
struct GoldengoApp: App {
    init() {
        // Notification actions: delegate + the owed-to-you category. Registered at launch so
        // action buttons work even for nudges scheduled by a previous run.
        let center = UNUserNotificationCenter.current()
        center.delegate = GoldengoNotificationDelegate.shared
        let logPayback = UNNotificationAction(identifier: LoanNudge.logPaybackActionID,
                                              title: "Log the payback…", options: [.foreground])
        let remindAgain = UNNotificationAction(identifier: LoanNudge.remindAgainActionID,
                                               title: "Remind me in a month")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: LoanNudge.categoryID,
                                   actions: [logPayback, remindAgain],
                                   intentIdentifiers: []),
        ])

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
                .task {
                    await GoldengoStore.refreshExchangeRates()
                    // Recompute the widget summaries AFTER rates land so a multi-currency today-total
                    // isn't published at yesterday's rates. RootView's own launch refresh can race
                    // ahead of the fetch; this one runs once the fresh rates are cached.
                    try? await GoldengoStore.shared().refreshSharedSummaries()
                }
        }
        .modelContainer(GoldengoStore.container)
    }
}
