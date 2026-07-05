import Foundation

/// Gates the notification-permission request to the FIRST cap ever set (any category), so
/// `CategoryDetailView` never re-prompts on every subsequent cap edit across the app's lifetime.
/// Thin glue: the actual `UNUserNotificationCenter` call is `LocalNotificationScheduler`'s existing
/// `requestAuthorization()` (reused, not reimplemented — same seam as subscription reminders).
enum BudgetNotificationPermission {
    private static let askedKey = "askedBudgetNotifPermission"

    /// Requests authorization once, ever, across the app's lifetime. Safe to call on every
    /// first-cap transition — the `UserDefaults` flag makes every call after the first a no-op.
    static func askOnce(defaults: UserDefaults = .standard) async {
        guard !defaults.bool(forKey: askedKey) else { return }
        defaults.set(true, forKey: askedKey)
        _ = await LocalNotificationScheduler.requestAuthorization()
    }
}
