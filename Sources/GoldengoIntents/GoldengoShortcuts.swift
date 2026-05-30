import AppIntents

@available(iOS 17.0, *)
public struct GoldengoShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: ["Log an expense in \(.applicationName)", "Add a \(.applicationName) expense"],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle"
        )
    }
}
