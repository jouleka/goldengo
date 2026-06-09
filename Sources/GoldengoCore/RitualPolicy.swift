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

        // Morning: in the morning window AND no intention captured yet today.
        if morningHours.contains(hour) {
            let setToday = intentionDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            if !setToday { return .morning }
        }
        // Evening: in the evening window (wraps past midnight) AND not reflected yet today.
        if hour >= eveningStartHour || hour < eveningEndHour {
            let reflectedToday = reflectedDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            if !reflectedToday { return .evening }
        }
        return .none
    }
}
