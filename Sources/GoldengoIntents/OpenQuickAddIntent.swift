import AppIntents
import GoldengoData

/// Opens the app at Quick-Add. Used by the Control Center control.
@available(iOS 17.0, *)
public struct OpenQuickAddIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Expense"
    public static let openAppWhenRun: Bool = true
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult {
        SharedSummary().setPendingTab(0)
        return .result()
    }
}
