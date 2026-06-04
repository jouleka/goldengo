import AppIntents
import Foundation
import GoldengoCore
import GoldengoData
import GoldengoIntents

// iOS auto-registers App Shortcuts only when BOTH the `AppShortcutsProvider` and the intent it
// references live in the app's main target — App Shortcut intents can't come from a framework / SPM
// package (the shortcut just won't appear). So the intent + provider live here; the shared save
// logic stays in `GoldengoIntents.ExpenseLogging` (unit-tested in the package).

/// The quick categories offered as a tap-list when logging from a gesture — mirrors the in-app chips,
/// each with its category icon. (The App Intents metadata processor requires `caseDisplayRepresentations`
/// to be a static dictionary literal, so the icons are inlined here to match `GoldengoCategoryIcon`.)
@available(iOS 17.0, *)
enum QuickExpenseCategory: String, AppEnum, CaseIterable {
    case groceries = "Groceries"
    case food = "Food"
    case transport = "Transport"
    case coffee = "Coffee"
    case bills = "Bills"
    case shopping = "Shopping"
    case other = "Other"

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Category" }
    static var caseDisplayRepresentations: [QuickExpenseCategory: DisplayRepresentation] {
        [
            .groceries: DisplayRepresentation(title: "Groceries", image: .init(systemName: "cart")),
            .food:      DisplayRepresentation(title: "Food",      image: .init(systemName: "fork.knife")),
            .transport: DisplayRepresentation(title: "Transport", image: .init(systemName: "car")),
            .coffee:    DisplayRepresentation(title: "Coffee",    image: .init(systemName: "cup.and.saucer")),
            .bills:     DisplayRepresentation(title: "Bills",     image: .init(systemName: "doc.text")),
            .shopping:  DisplayRepresentation(title: "Shopping",  image: .init(systemName: "bag")),
            .other:     DisplayRepresentation(title: "Other",     image: .init(systemName: "tag")),
        ]
    }
}

@available(iOS 17.0, *)
struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Expense"
    static let description = IntentDescription("Quickly log an expense in Goldengo without opening the app.")

    @Parameter(title: "Category") var category: QuickExpenseCategory
    @Parameter(title: "Amount") var amount: Double

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$category) for \(\.$amount)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = GoldengoStore.shared()
        let currency = SharedSummary().readPreferredCurrency().rawValue
        // Save and return NO dialog, so triggering it (e.g. via Back Tap) shows only the system's
        // brief auto-dismissing banner — there's no "Done" to tap.
        _ = try await ExpenseLogging.log(amount: Decimal(amount), currencyCode: currency,
                                         merchant: nil, categoryName: category.rawValue, store: store)
        return .result()
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
