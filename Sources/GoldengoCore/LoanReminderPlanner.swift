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
    /// How many upcoming nudges to keep queued per loan. Ignoring one must never end the
    /// nudging — the next ones are already scheduled even if the app isn't opened for months.
    public static let scheduledOccurrences = 3

    /// The next `scheduledOccurrences` monthly nudges per loan, on the grid
    /// lastEvent + 30·k days, future dates only (a fired nudge is gone; re-syncing queues
    /// the NEXT dates). Disabled → [] (the caller's replace-sync clears stale nudges).
    public static func plan(_ loans: [LoanInput], enabled: Bool,
                            now: Date, calendar: Calendar) -> [Request] {
        guard enabled else { return [] }
        return loans.flatMap { loan -> [Request] in
            var requests: [Request] = []
            var k = 1
            while requests.count < scheduledOccurrences && k < 1000 {
                defer { k += 1 }
                guard let fire = calendar.date(byAdding: .day, value: nudgeAfterDays * k,
                                               to: loan.lastEventDate) else { break }
                guard fire > now else { continue }
                let age = k == 1 ? "a month" : "\(k) months"
                requests.append(Request(id: "\(loan.id)#\(k)",
                                        title: "\(loan.personName) still owes you",
                                        body: "\(loan.remainingText) has been out for \(age). Worth a nudge?",
                                        fireDate: fire))
            }
            return requests
        }
    }
}

/// Identifiers shared between the package (which schedules loan nudges) and the app target
/// (which registers the notification category + actions and handles the responses).
public enum LoanNudge {
    public static let notificationPrefix = "loan-reminder:"
    public static let categoryID = "LOAN_NUDGE"
    /// Queues one fresh nudge a month out, straight from the notification (no app open).
    public static let remindAgainActionID = "LOAN_REMIND_AGAIN"
    /// Foreground action: opens the app on the Wallet tab to log the payback honestly
    /// (never fabricates a repayment from a button — the amount is the user's call).
    public static let logPaybackActionID = "LOAN_LOG_PAYBACK"
}
