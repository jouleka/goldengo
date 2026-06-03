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
    public static let description = IntentDescription("Quickly log an expense in Goldengo without opening the app.")

    @Parameter(title: "What's it for?") public var note: String
    @Parameter(title: "Amount") public var amount: Double

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$note) for \(\.$amount)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = IntentEnvironment.storeProvider?() else {
            return .result(dialog: "Goldengo isn't ready yet.")
        }
        let currency = SharedSummary().readPreferredCurrency().rawValue
        let summary = try await ExpenseLogging.log(amount: Decimal(amount), currencyCode: currency,
                                                   merchant: nil, note: note, categoryName: nil, store: store)
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}
