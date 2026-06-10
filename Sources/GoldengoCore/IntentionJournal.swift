import Foundation

/// One saved morning intention (GOL-93). Codable for the SharedSummary JSON blob.
public struct IntentionEntry: Codable, Equatable, Sendable {
    public var date: Date
    public var text: String
    public init(date: Date, text: String) { self.date = date; self.text = text }
}

/// Pure journal rules for past intentions: same-day saves replace (editing the morning note
/// never duplicates) and the journal is capped — persistence is the caller's concern.
public enum IntentionJournal {
    public static let capacity = 365

    /// Append `entry`, replacing an existing same-calendar-day entry, dropping the oldest
    /// beyond `capacity`. Input and output are oldest-first (newest LAST).
    public static func append(_ entry: IntentionEntry, to history: [IntentionEntry],
                              calendar: Calendar) -> [IntentionEntry] {
        var kept = history.filter { !calendar.isDate($0.date, inSameDayAs: entry.date) }
        kept.append(entry)
        if kept.count > capacity { kept.removeFirst(kept.count - capacity) }
        return kept
    }
}
