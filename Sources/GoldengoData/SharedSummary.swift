import Foundation

public struct SharedSummary {
    public struct Snapshot: Equatable { public var todayTotalText: String; public var redacted: Bool }
    private let defaults: UserDefaults
    public static let appGroupID = "group.com.goldengo.app"

    public init(suiteName: String? = SharedSummary.appGroupID) {
        defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }
    public func write(todayTotalText: String, redacted: Bool) {
        defaults.set(todayTotalText, forKey: "todayTotalText")
        defaults.set(redacted, forKey: "redacted")
    }
    public func read() -> Snapshot {
        Snapshot(todayTotalText: defaults.string(forKey: "todayTotalText") ?? "—",
                 redacted: defaults.bool(forKey: "redacted"))
    }
}
