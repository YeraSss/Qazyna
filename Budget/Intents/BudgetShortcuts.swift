import AppIntents

/// Exposes the app's intents to Shortcuts / Siri / Spotlight. `LogTransactionIntent` is the
/// action the user maps inside their Wallet/Transaction automation.
struct BudgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTransactionIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Log a tap in \(.applicationName)"
            ],
            shortTitle: "Log Apple Pay Expense",
            systemImageName: "creditcard.fill"
        )
        AppShortcut(
            intent: OpenQuickAddIntent(),
            phrases: [
                "Add an expense in \(.applicationName)",
                "New transaction in \(.applicationName)"
            ],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle.fill"
        )
    }
}
