import Foundation
import GoldengoCore
import GoldengoData
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Fires an immediate local notification for each newly-escalated budget alert. Thin glue over
/// `UNUserNotificationCenter` — all the escalation/dedupe logic lives in
/// `IngestionStore.evaluateBudgetAlerts` (the caller decides WHEN to evaluate; this only delivers
/// the result). Mirrors `LocalNotificationScheduler`'s patterns (prefix convention, `isRunningTests`
/// guard, `#if canImport(UserNotifications)`), kept as its own small type since it fires immediately
/// (`trigger: nil`) rather than scheduling — a distinct shape from the reminders' 09:00 calendar grid.
public enum OverspendNotifications {
    public static let prefix = "overspend:"

    /// Same bundle-less-xctest guard as `LocalNotificationScheduler.isRunningTests` — duplicated
    /// (not shared) because that one is `private` to its own type; the logic must stay identical.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// Posts one notification per alert, identifier `prefix + categoryName + ":" + level.rawValue`
    /// so a re-fire for the same category/level (shouldn't happen — the store dedupes) replaces
    /// rather than stacks. No-op under tests and where `UserNotifications` isn't available.
    public static func fire(_ alerts: [BudgetAlert]) async {
        #if canImport(UserNotifications)
        guard !isRunningTests else { return }
        let center = UNUserNotificationCenter.current()
        for a in alerts {
            let spent = Money(amount: a.spent, currency: CurrencyCode(a.currencyCode)).formatted()
            let cap = Money(amount: a.budget, currency: CurrencyCode(a.currencyCode)).formatted()
            let content = UNMutableNotificationContent()
            if a.level == .over {
                content.title = "Over budget on \(a.categoryName)"
                content.body = "You've spent \(spent) of your \(cap) cap this month."
            } else {
                content.title = "Close to your \(a.categoryName) cap"
                content.body = "\(spent) spent of \(cap) this month."
            }
            content.sound = .default
            content.categoryIdentifier = prefix
            let request = UNNotificationRequest(
                identifier: prefix + a.categoryName + ":" + a.level.rawValue,
                content: content,
                trigger: nil)   // nil = deliver immediately, unlike the reminders' calendar trigger
            try? await center.add(request)
        }
        #endif
    }
}
