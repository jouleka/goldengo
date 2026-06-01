import Foundation

/// Pure logic for WHICH subscription reminders to schedule and WHEN. The OS scheduling glue lives
/// in the Features layer (`LocalNotificationScheduler`); this stays trivially unit-testable.
public enum SubscriptionReminderPlanner {
    public struct ReminderInput: Sendable, Equatable {
        public var id: String          // subscription matchKey
        public var title: String
        public var body: String
        public var nextCharge: Date
        public init(id: String, title: String, body: String, nextCharge: Date) {
            self.id = id; self.title = title; self.body = body; self.nextCharge = nextCharge
        }
    }
    public struct ReminderRequest: Sendable, Equatable {
        public var id: String
        public var title: String
        public var body: String
        public var fireDate: Date
        public init(id: String, title: String, body: String, fireDate: Date) {
            self.id = id; self.title = title; self.body = body; self.fireDate = fireDate
        }
    }

    /// Fire `leadDays` before each next-charge, dropping any whose fire date is already before `now`.
    /// Works off the START OF the charge's day (in `calendar`) so the result is a clean day boundary:
    /// `nextCharge`'s time-of-day traces back to a raw transaction timestamp under a UTC calendar, and
    /// carrying it would risk firing at an odd local hour or rolling to an adjacent local day. The
    /// scheduler pins the fire hour (09:00 local); here we only care about the correct day.
    public static func plan(_ inputs: [ReminderInput], leadDays: Int, now: Date,
                            calendar: Calendar) -> [ReminderRequest] {
        inputs.compactMap { input in
            let chargeDay = calendar.startOfDay(for: input.nextCharge)
            guard let fire = calendar.date(byAdding: .day, value: -leadDays, to: chargeDay),
                  fire >= now else { return nil }
            return ReminderRequest(id: input.id, title: input.title, body: input.body, fireDate: fire)
        }
    }
}
