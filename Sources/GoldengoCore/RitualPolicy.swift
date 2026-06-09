import Foundation

/// Which same-day ritual prompt is due right now.
public enum RitualPrompt: Sendable, Equatable { case morning, evening, none }

/// Pure decision: given the clock and the last intention/reflection dates, decide which prompt
/// (if any) should present. No persistence, no UI. Uses the LOCAL calendar by default — the
/// user's day boundaries are what "today" means here.
public enum RitualPolicy {
    public static let morningHours = 5..<12   // [05:00, 12:00)
    public static let eveningStartHour = 18   // evening window is 18:00 .. 04:00 next day
    public static let eveningEndHour = 4

    public static func prompt(now: Date, intentionDate: Date?, reflectedDate: Date?,
                              calendar: Calendar = .current) -> RitualPrompt {
        let hour = calendar.component(.hour, from: now)

        // Morning: in the morning window AND no intention captured yet today. The morning window
        // (5..<12) never crosses midnight, so a plain same-calendar-day check is correct here.
        if morningHours.contains(hour) {
            let setToday = intentionDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            if !setToday { return .morning }
        }
        // Evening: in the evening window (18:00..04:00, wraps past midnight) AND not yet reflected
        // THIS evening session. Suppression is keyed on the session — NOT the calendar day — because
        // the window crosses midnight: a reflection finished at 23:00 must still suppress a 01:00
        // re-open the same night (a calendar-day check would wrongly re-present it, since 23:00 and
        // 01:00 fall on different dates). A reflection from a *prior* session is before this
        // session's 18:00 start, so the next night is correctly eligible again.
        if hour >= eveningStartHour || hour < eveningEndHour {
            let sessionStart = eveningSessionStart(for: now, calendar: calendar)
            let reflectedThisSession = reflectedDate.map { $0 >= sessionStart } ?? false
            if !reflectedThisSession { return .evening }
        }
        return .none
    }

    /// The 18:00 boundary that opened the evening session containing `now`. For an after-midnight
    /// `now` (hour < eveningEndHour) the session opened at 18:00 on the PREVIOUS calendar day.
    static func eveningSessionStart(for now: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: now)
        let baseDay = hour < eveningEndHour ? calendar.date(byAdding: .day, value: -1, to: now)! : now
        return calendar.date(byAdding: .hour, value: eveningStartHour, to: calendar.startOfDay(for: baseDay))!
    }
}
