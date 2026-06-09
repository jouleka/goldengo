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
