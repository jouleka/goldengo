import AppIntents
import Foundation
import GoldengoCore
import GoldengoData

/// The app sets this at launch so the intent reaches the shared on-disk store
/// WITHOUT the package depending on the app target.
@MainActor public enum IntentEnvironment {
    public static var storeProvider: (@MainActor () -> IngestionStore)?
}

@available(iOS 17.0, macOS 14.0, *)
public struct LogExpenseIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Expense"
    public static let description = IntentDescription("Quickly log an expense in Goldengo.")

    @Parameter(title: "Amount") public var amount: Double
    @Parameter(title: "Category") public var category: String?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = IntentEnvironment.storeProvider?() else {
            return .result(dialog: "Goldengo isn't ready yet.")
        }
        let summary = try await ExpenseLogging.log(amount: Decimal(amount), currencyCode: "ALL",
                                                   merchant: nil, categoryName: category, store: store)
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}
