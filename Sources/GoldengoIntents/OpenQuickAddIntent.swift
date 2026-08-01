import AppIntents
import GoldengoData

/// Opens the app at Quick-Add. Used by the Control Center control.
@available(iOS 17.0, *)
public struct OpenQuickAddIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Expense"
    public static let openAppWhenRun: Bool = true
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult {
        Self.stageQuickAdd()
        return .result()
    }

    /// The intent's whole effect, extracted sync so it stays testable: async tests cannot
    /// run in an AppIntents-linked xctest process (the async bridge abandons them —
    /// see ExpenseLogging's doc note), so the test covers this and perform() stays a
    /// one-line wrapper.
    @MainActor public static func stageQuickAdd() {
        SharedSummary().setPendingTab(0)
    }
}
