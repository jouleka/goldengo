import Foundation

/// Pure decision for the Re-entry soft-landing: how many whole days since the last session, and
/// whether that warrants the welcome-back screen. UTC calendar; no persistence/UI dependency.
public enum ReEntryPolicy {
    public static let thresholdDays = 4

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    /// Whole days between `lastSeen` and `now`, or nil when there's no prior session or the gap is
    /// non-positive (same-day reopen / clock skew) — so the caller never shows a nonsensical landing.
    public static func daysAway(lastSeen: Date?, now: Date = .now) -> Int? {
        guard let lastSeen else { return nil }
        let days = calendar.dateComponents([.day], from: lastSeen, to: now).day ?? 0
        return days > 0 ? days : nil
    }

    public static func shouldShow(lastSeen: Date?, now: Date = .now) -> Bool {
        (daysAway(lastSeen: lastSeen, now: now) ?? 0) >= thresholdDays
    }
}
