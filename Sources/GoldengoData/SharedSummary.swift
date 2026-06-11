import Foundation
import GoldengoCore

public struct SharedSummary {
    public struct Snapshot: Equatable {
        public var todayTotalText: String
        public var revealOnLockScreen: Bool
    }
    private let defaults: UserDefaults
    public static let appGroupID = "group.com.goldengo.app"
    public static let revealKey = "revealOnLockScreen"
    public static let remindBeforeChargesKey = "remindBeforeCharges"
    public static let reminderLeadDaysKey = "reminderLeadDays"
    public static let preferredCurrencyKey = "preferredCurrency"
    private static let totalKey = "todayTotalText"
    private static let totalDateKey = "todayTotalDate"
    private static let pendingTabKey = "pendingTab"

    public init(suiteName: String? = SharedSummary.appGroupID) {
        defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func writeTodayTotal(_ text: String, asOf date: Date = .now) {
        defaults.set(text, forKey: Self.totalKey)
        defaults.set(date, forKey: Self.totalDateKey)
    }
    public func setRevealOnLockScreen(_ on: Bool) { defaults.set(on, forKey: Self.revealKey) }

    /// The user's preferred/display currency (ISO code). Defaults to lek when unset.
    public func readPreferredCurrency() -> CurrencyCode {
        let raw = defaults.string(forKey: Self.preferredCurrencyKey) ?? ""
        return raw.isEmpty ? .all : CurrencyCode(raw)
    }

    public func setPreferredCurrency(_ code: CurrencyCode) {
        defaults.set(code.rawValue, forKey: Self.preferredCurrencyKey)
    }

    public static let lastSeenKey = "lastSeen"
    /// When the app was last foregrounded/backgrounded — drives the Re-entry soft-landing (GOL-84).
    public func setLastSeen(_ date: Date = .now) { defaults.set(date, forKey: Self.lastSeenKey) }
    public func readLastSeen() -> Date? { defaults.object(forKey: Self.lastSeenKey) as? Date }

    // MARK: Daily check-in ritual (GOL-85) — opt-in morning intention + evening reflection.
    public static let ritualEnabledKey = "ritualEnabled"
    public static let intentionKey = "ritualIntention"
    public static let intentionDateKey = "ritualIntentionDate"
    public static let reflectedDateKey = "ritualReflectedDate"

    public func setRitualEnabled(_ on: Bool) { defaults.set(on, forKey: Self.ritualEnabledKey) }
    public func ritualEnabled() -> Bool { defaults.bool(forKey: Self.ritualEnabledKey) }

    /// Store today's morning intention text + the moment it was captured, and journal it
    /// (same-day re-saves replace their journal entry — IntentionJournal rules).
    public func setIntention(_ text: String, on date: Date = .now) {
        defaults.set(text, forKey: Self.intentionKey)
        defaults.set(date, forKey: Self.intentionDateKey)
        setIntentionHistory(IntentionJournal.append(IntentionEntry(date: date, text: text),
                                                    to: readIntentionHistory(), calendar: .current))
    }
    /// The stored intention, or nil if either the text or its date is missing.
    public func readIntention() -> (text: String, date: Date)? {
        guard let text = defaults.string(forKey: Self.intentionKey),
              let date = defaults.object(forKey: Self.intentionDateKey) as? Date else { return nil }
        return (text, date)
    }
    public func readIntentionDate() -> Date? { defaults.object(forKey: Self.intentionDateKey) as? Date }

    /// Mark that the evening reflection was completed at `date`.
    public func setReflected(on date: Date = .now) { defaults.set(date, forKey: Self.reflectedDateKey) }
    public func readReflectedDate() -> Date? { defaults.object(forKey: Self.reflectedDateKey) as? Date }

    // GOL-98: the pocket widget's pre-rendered content (revealed + hidden variants).
    public static let pocketPayloadKey = "pocketPayload"
    public func writePocketPayload(_ p: PocketPayload) {
        defaults.set((try? JSONEncoder().encode(p)) ?? Data(), forKey: Self.pocketPayloadKey)
    }
    public func readPocketPayload() -> PocketPayload? {
        guard let data = defaults.data(forKey: Self.pocketPayloadKey),
              let p = try? JSONDecoder().decode(PocketPayload.self, from: data) else { return nil }
        return p
    }

    // GOL-98: one-shot flag — the pocket widget tap should land ON the Adjust screen.
    public static let pendingWalletAdjustKey = "pendingWalletAdjust"
    public func setPendingWalletAdjust(_ on: Bool) { defaults.set(on, forKey: Self.pendingWalletAdjustKey) }
    public func readPendingWalletAdjust() -> Bool { defaults.bool(forKey: Self.pendingWalletAdjustKey) }

    // GOL-97: a same-day skip marker so the morning prompt presents at most once per day.
    public static let ritualSkippedDateKey = "ritualSkippedDate"
    public func setMorningSkipped(on date: Date = .now) { defaults.set(date, forKey: Self.ritualSkippedDateKey) }
    public func readMorningSkippedDate() -> Date? { defaults.object(forKey: Self.ritualSkippedDateKey) as? Date }

    // GOL-93 extras: schedulable nudge times + the intention journal.
    public static let ritualMorningMinutesKey = "ritualMorningMinutes"
    public static let ritualEveningMinutesKey = "ritualEveningMinutes"
    public static let ritualIntentionHistoryKey = "ritualIntentionHistory"

    /// Nudge times as minutes-from-midnight — Ints avoid Date/timezone traps. Unset reads as
    /// the shipped defaults (object(forKey:) nil-check, NOT integer(forKey:), which would
    /// silently turn "unset" into midnight).
    public func setRitualMorningMinutes(_ m: Int) { defaults.set(m, forKey: Self.ritualMorningMinutesKey) }
    public func ritualMorningMinutes() -> Int {
        defaults.object(forKey: Self.ritualMorningMinutesKey) as? Int ?? RitualPolicy.defaultMorningNudgeMinutes
    }
    public func setRitualEveningMinutes(_ m: Int) { defaults.set(m, forKey: Self.ritualEveningMinutesKey) }
    public func ritualEveningMinutes() -> Int {
        defaults.object(forKey: Self.ritualEveningMinutesKey) as? Int ?? RitualPolicy.defaultEveningNudgeMinutes
    }

    /// The intention journal, JSON-encoded. Corrupt/missing → [] (restart, never crash).
    public func readIntentionHistory() -> [IntentionEntry] {
        guard let data = defaults.data(forKey: Self.ritualIntentionHistoryKey),
              let entries = try? JSONDecoder().decode([IntentionEntry].self, from: data) else { return [] }
        return entries
    }
    public func setIntentionHistory(_ entries: [IntentionEntry]) {
        defaults.set((try? JSONEncoder().encode(entries)) ?? Data(), forKey: Self.ritualIntentionHistoryKey)
    }

    public func setPendingTab(_ tab: Int?) {
        if let tab {
            defaults.set(tab, forKey: Self.pendingTabKey)
        } else {
            defaults.removeObject(forKey: Self.pendingTabKey)
        }
    }

    public func readPendingTab() -> Int? {
        guard defaults.object(forKey: Self.pendingTabKey) != nil else { return nil }
        return defaults.integer(forKey: Self.pendingTabKey)
    }

    public func read() -> Snapshot {
        Snapshot(todayTotalText: defaults.string(forKey: Self.totalKey) ?? "—",
                 revealOnLockScreen: defaults.bool(forKey: Self.revealKey))
    }

    /// The total to show *for today*: the cached value if it was computed today, otherwise zero in the
    /// preferred currency (a new day with nothing logged yet — or never written). The widget uses this
    /// so it never shows a previous day's total.
    public func todayDisplayText(now: Date = .now) -> String {
        if let text = defaults.string(forKey: Self.totalKey),
           let date = defaults.object(forKey: Self.totalDateKey) as? Date,
           Calendar.current.isDate(date, inSameDayAs: now) {
            return text
        }
        return Money(amount: 0, currency: readPreferredCurrency()).formatted()
    }
}
