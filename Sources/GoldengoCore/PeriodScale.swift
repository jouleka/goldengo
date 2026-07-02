import Foundation

/// A half-open time window `[start, end)`. Half-open so adjacent periods tile the timeline with no
/// overlap and no gap: the first instant of next month belongs to next month, never this one.
public struct PeriodRange: Equatable, Sendable {
    public let start: Date   // inclusive
    public let end: Date     // exclusive
    public init(start: Date, end: Date) { self.start = start; self.end = end }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// True once this period has fully elapsed by `now` — i.e. a later period exists to step to.
    /// The period *containing* `now` returns false, which is what stops the browser stepping into
    /// the future.
    public func hasFullyElapsed(by now: Date) -> Bool { end <= now }
}

/// The granularity of the History browser's toggle. Each case knows how to find its period around a
/// date, step to an adjacent one, and label itself. All pure — no storage, no I/O — so it's the
/// fully-testable reliability core the UI sits on.
public enum PeriodScale: String, CaseIterable, Sendable, Identifiable {
    case day, week, month, year
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        case .year:  return "Year"
        }
    }

    /// The `Calendar` component this scale maps to. `.weekOfYear` (not `.weekday`) so the week is a
    /// whole locale-aware week.
    private var component: Calendar.Component {
        switch self {
        case .day:   return .day
        case .week:  return .weekOfYear
        case .month: return .month
        case .year:  return .year
        }
    }

    /// The `[start, end)` period of this scale containing `date`. Delegates to
    /// `Calendar.dateInterval(of:for:)`, which already honours first-weekday, month length, leap
    /// years, and DST — so boundary arithmetic is never hand-rolled here.
    public func range(containing date: Date, calendar: Calendar = .current) -> PeriodRange {
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            let start = calendar.startOfDay(for: date)
            return PeriodRange(start: start, end: start)
        }
        return PeriodRange(start: interval.start, end: interval.end)
    }

    /// Move `date` by `steps` whole units of this scale (negative = into the past). The result is an
    /// anchor *inside* the target period; pair with `range(containing:)` to get its bounds.
    public func anchor(_ date: Date, steppedBy steps: Int, calendar: Calendar = .current) -> Date {
        let comp: Calendar.Component = self == .week ? .weekOfYear : component
        return calendar.date(byAdding: comp, value: steps, to: date) ?? date
    }

    /// A human label for `range`. Relative words ("Today"/"Yesterday"/"This week"/"This month") only
    /// when the range actually contains `now`; otherwise a concrete date/period.
    public func label(for range: PeriodRange, now: Date,
                      calendar: Calendar = .current, locale: Locale = .current) -> String {
        var fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = locale
        fmt.timeZone = calendar.timeZone

        let sameYearAsNow = calendar.component(.year, from: range.start) == calendar.component(.year, from: now)
        switch self {
        case .day:
            if calendar.isDate(range.start, inSameDayAs: now) { return "Today" }
            if let yday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
               calendar.isDate(range.start, inSameDayAs: yday) { return "Yesterday" }
            // Carry the year once the day isn't in the current year, else two same-day labels a year
            // apart are indistinguishable while stepping back (the stepper is the only period id).
            fmt.setLocalizedDateFormatFromTemplate(sameYearAsNow ? "EEE d MMM" : "EEE d MMM y")
            return fmt.string(from: range.start)
        case .week:
            if range.contains(now) { return "This week" }
            return Self.weekLabel(range, now: now, calendar: calendar, fmt: fmt)
        case .month:
            fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return fmt.string(from: range.start)
        case .year:
            fmt.setLocalizedDateFormatFromTemplate("yyyy")
            return fmt.string(from: range.start)
        }
    }

    /// "Jun 22 – 28" (same month, current year), "Jun 29 – Jul 5" (cross-month), "Jun 10 – 16, 2024"
    /// (prior year), "Dec 29, 2025 – Jan 4, 2026" (straddling the year boundary). `range.end` is
    /// exclusive, so the inclusive last day is one day before it. The year is shown whenever the week
    /// isn't wholly in the current year, so two visually-identical weeks a year apart can't be confused.
    private static func weekLabel(_ range: PeriodRange, now: Date, calendar: Calendar, fmt: DateFormatter) -> String {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.start
        let startYear = calendar.component(.year, from: range.start)
        let endYear = calendar.component(.year, from: lastDay)
        let nowYear = calendar.component(.year, from: now)
        fmt.setLocalizedDateFormatFromTemplate("MMM d")
        let startStr = fmt.string(from: range.start)

        if startYear != endYear {
            return "\(startStr), \(startYear) – \(fmt.string(from: lastDay)), \(endYear)"
        }
        let sameMonth = calendar.component(.month, from: range.start) == calendar.component(.month, from: lastDay)
        if sameMonth { fmt.setLocalizedDateFormatFromTemplate("d") }   // "MMM d – d"; else keep "MMM d – MMM d"
        let base = "\(startStr) – \(fmt.string(from: lastDay))"
        return startYear == nowYear ? base : "\(base), \(startYear)"
    }
}
