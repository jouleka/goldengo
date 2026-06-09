import Foundation
import GoldengoCore
import GoldengoData
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Pure mapping from confirmed subscription snapshots to reminder inputs.
public enum SubscriptionReminders {
    /// Build reminder inputs from CONFIRMED candidates only (the user opted in by confirming).
    public static func inputs(from candidates: [SubscriptionSnapshot]) -> [SubscriptionReminderPlanner.ReminderInput] {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        return candidates.filter { $0.isConfirmed }.map { s in
            let money = Money(amount: s.amount, currency: CurrencyCode(s.currencyCode)).formatted()
            return SubscriptionReminderPlanner.ReminderInput(
                id: s.id,
                title: "\(s.displayName) renews soon",
                body: "About \(money) on \(df.string(from: s.nextChargeDate)).",
                nextCharge: s.nextChargeDate)
        }
    }

    /// The full, pure decision the UI needs: returns the reminders to schedule given the toggle state
    /// and stored lead-days. Returns [] when disabled (so the caller's `sync([])` clears any stale
    /// reminders — self-healing). `leadDays` is clamped to >= 1: `UserDefaults.integer` yields 0 when
    /// the key is unset, which must coincide with the @AppStorage default (1) and the stepper min (1).
    public static func plannedRequests(enabled: Bool, leadDays: Int, candidates: [SubscriptionSnapshot],
                                       now: Date, calendar: Calendar) -> [SubscriptionReminderPlanner.ReminderRequest] {
        guard enabled else { return [] }
        return SubscriptionReminderPlanner.plan(inputs(from: candidates),
                                                leadDays: max(1, leadDays), now: now, calendar: calendar)
    }
}

/// Thin glue over `UNUserNotificationCenter`. All decision logic is in `SubscriptionReminderPlanner`
/// / `SubscriptionReminders` (pure, tested); this only requests authorization and registers requests.
public enum LocalNotificationScheduler {
    private static let prefix = "sub-reminder:"

    /// Requests authorization (alert + sound). Returns whether granted. No-op off-device.
    @discardableResult
    public static func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        #else
        return false
        #endif
    }

    /// Replace our pending subscription reminders with exactly `requests` (idempotent re-sync).
    public static func sync(_ requests: [SubscriptionReminderPlanner.ReminderRequest]) async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        for r in requests {
            let content = UNMutableNotificationContent()
            content.title = r.title; content.body = r.body; content.sound = .default
            // Fire at 09:00 local on the planner-computed day. We take ONLY the day from fireDate and
            // pin a sane hour — the planner already did the "N days before" math on a day boundary.
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: r.fireDate)
            comps.hour = 9; comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + r.id, content: content, trigger: trigger))
        }
        #endif
    }

    /// Cancel all of our pending subscription reminders.
    public static func cancelAll() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        #endif
    }

    private static let ritualPrefix = "ritual:"

    /// Schedule the two daily check-in nudges (08:00 morning, 21:00 evening), repeating.
    /// Idempotent: clears our prior ritual requests first. Best-effort no-op when notifications
    /// aren't authorized/available. Leaves `sub-reminder:` requests untouched (distinct prefix).
    public static func scheduleRitual() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(ritualPrefix) })

        func add(_ id: String, hour: Int, title: String, body: String) async {
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            var comps = DateComponents(); comps.hour = hour; comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: ritualPrefix + id,
                                                        content: content, trigger: trigger))
        }
        await add("morning", hour: 8, title: "Set today's intention", body: "What's today about?")
        await add("evening", hour: 21, title: "Close your day", body: "A calm look back at today.")
        #endif
    }

    /// Cancel both daily ritual nudges (leaves subscription reminders intact).
    public static func cancelRitual() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(ritualPrefix) })
        #endif
    }
}
