import AppIntents
import Foundation
import GoldengoCore
import GoldengoData
import GoldengoIntents

// iOS auto-registers App Shortcuts only when BOTH the `AppShortcutsProvider` and the intent it
// references live in the app's main target — App Shortcut intents can't come from a framework / SPM
// package (the shortcut just won't appear). So the intent + provider live here; the shared save
// logic stays in `GoldengoIntents.ExpenseLogging` (unit-tested in the package).

@available(iOS 17.0, *)
struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Expense"
    static let description = IntentDescription("Quickly log an expense in Goldengo without opening the app.")

    @Parameter(title: "What's it for?") var note: String
    @Parameter(title: "Amount") var amount: Double

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$note) for \(\.$amount)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = GoldengoStore.shared()
        let currency = SharedSummary().readPreferredCurrency().rawValue
        let summary = try await ExpenseLogging.log(amount: Decimal(amount), currencyCode: currency,
                                                   merchant: nil, note: note, categoryName: nil, store: store)
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

@available(iOS 17.0, *)
struct GoldengoAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: ["Log an expense in \(.applicationName)", "Add a \(.applicationName) expense"],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle"
        )
    }
}
