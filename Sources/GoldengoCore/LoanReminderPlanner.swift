import Foundation

/// Pure planner for "owed to you" nudges: one reminder per open loan, firing 30 days after
/// its newest event (a fresh lend or a payback re-arms the clock — the caller replans after
/// every mutation, and the scheduler replaces by id prefix, so stale requests self-heal).
/// The caller passes only OPEN loans (balance > 0); closed loans simply stop appearing and
/// their pending request is cleared by the replace-sync.
public enum LoanReminderPlanner {
    public struct LoanInput: Sendable, Equatable {
        public var id: String            // LoanRecord id
        public var personName: String
        public var remainingText: String // preformatted Money string (e.g. "ALL 5,000")
        public var lastEventDate: Date   // newest lent/repayment event
        public init(id: String, personName: String, remainingText: String, lastEventDate: Date) {
            self.id = id; self.personName = personName
            self.remainingText = remainingText; self.lastEventDate = lastEventDate
        }
    }

    /// Shape-compatible with the notification scheduler's request.
    public struct Request: Sendable, Equatable {
        public var id: String
        public var title: String
        public var body: String
        public var fireDate: Date
        public init(id: String, title: String, body: String, fireDate: Date) {
            self.id = id; self.title = title; self.body = body; self.fireDate = fireDate
        }
    }

    public static let nudgeAfterDays = 30

    /// Disabled → [] (the caller's replace-sync then clears any stale nudges — self-healing).
    public static func plan(_ loans: [LoanInput], enabled: Bool,
                            now: Date, calendar: Calendar) -> [Request] {
        guard enabled else { return [] }
        return loans.compactMap { loan in
            guard let fire = calendar.date(byAdding: .day, value: nudgeAfterDays,
                                           to: loan.lastEventDate) else { return nil }
            return Request(id: loan.id,
                           title: "\(loan.personName) still owes you",
                           body: "\(loan.remainingText) has been out for a month. Worth a nudge?",
                           fireDate: fire)
        }
    }
}
