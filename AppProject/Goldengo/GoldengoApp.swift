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
final class GoldengoNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    // @unchecked: the class is stateless (methods only); Sendable can't be checked through NSObject.
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
        if request.identifier.hasPrefix(OverspendNotifications.prefix) {
            // No action buttons (see the category registration below) — a tap just routes to
            // Home, the nearest thing to a "Spending screen" entry the pendingTab handoff exposes
            // (the full breakdown is pushed from there, same as the on-screen "See all ›").
            SharedSummary().setPendingTab(1)
            completionHandler(); return
        }
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
            UNNotificationCategory(identifier: OverspendNotifications.prefix,
                                   actions: [], intentIdentifiers: []),
        ])

    }
    #if DEBUG && targetEnvironment(simulator)
    @State private var sampleReady = ProcessInfo.processInfo.environment["GOLDENGO_SEED_SAMPLE"] != "1"
    #endif
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if !sampleReady {
                    ProgressView().task {
                        await seedScreenshotSample()
                        sampleReady = true
                    }
                } else {
                    appContent
                }
                #else
                appContent
                #endif
            }
        }
        .modelContainer(GoldengoStore.container)
    }

    private var appContent: some View {
        RootView(store: GoldengoStore.shared(), storageStatus: GoldengoStore.storageMode.title)
            .task {
                await GoldengoStore.refreshExchangeRates()
                try? await GoldengoStore.shared().refreshSharedSummaries()
            }
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Synthetic simulator-only records. Never compiled into the distributed app.
    @MainActor
    private func seedScreenshotSample() async {
        let defaults = UserDefaults(suiteName: SharedSummary.appGroupID) ?? .standard
        SharedSummary().setPreferredCurrency(.eur)
        defaults.set(true, forKey: SharedSummary.periodSetupDeferredKey)
        if let tab = ProcessInfo.processInfo.environment["GOLDENGO_SCREENSHOT_TAB"].flatMap(Int.init) {
            SharedSummary().setPendingTab(tab)
        }
        let store = GoldengoStore.shared()
        // Keep relaunches stable without deleting records from the simulator.
        guard !defaults.bool(forKey: "appStoreScreenshotSampleV1") else { return }
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: .now))!
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        try? await store.setSpendingPeriod(startDate: start, endDate: end, fundingMode: .fixedAmount,
                                          startingAmount: 1450, currency: .eur, cadence: .monthly)
        try? await store.logIncome(amount: 1900, currency: .eur, sourceName: "Monthly pay", date: start)
        for (amount, merchant, category, days) in [(Decimal(42), "Weekly groceries", "Food", 1),
            (18, "Coffee with friends", "Food", 0), (29, "Train tickets", "Transport", 2),
            (65, "New trainers", "Shopping", 3)] {
            _ = try? await store.logManual(amount: amount, currency: .eur, merchant: merchant,
                    categoryName: category, date: calendar.date(byAdding: .day, value: -days, to: .now)!)
        }
        _ = try? await store.setMonthlyBudget(categoryNamed: "Food", cap: 300, currency: .eur)
        _ = try? await store.setMonthlyBudget(categoryNamed: "Transport", cap: 100, currency: .eur)
        try? await store.addGoal(name: "Weekend away", targetAmount: 450, savedAmount: 120,
                                 currency: .eur, dueDate: nil)
        try? await store.addManualSubscription(name: "Music", amount: 9.99, currency: .eur,
                  cadence: .monthly, nextChargeDate: calendar.date(byAdding: .day, value: 4, to: .now)!)
        defaults.set(true, forKey: "appStoreScreenshotSampleV1")
    }
    #endif
}
