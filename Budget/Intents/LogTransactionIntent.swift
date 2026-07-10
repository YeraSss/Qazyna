import AppIntents
import SwiftData
import Foundation

/// The App Intent the Shortcuts "Transaction"/"Wallet" automation calls when the user taps
/// to pay with Apple Pay. `openAppWhenRun = false` so it runs in the background without
/// launching the UI. It bootstraps its own `ModelContainer` against the shared App Group
/// store, resolves the account/category, and logs via `TapLogger` (idempotent by dedupKey).
struct LogTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Apple Pay Expense"
    static var description = IntentDescription(
        "Logs a tap-to-pay purchase to Qazyna. Map this to a Wallet/Transaction automation and pass the Amount and Merchant.")
    static var openAppWhenRun = false
    static var isDiscoverable = true

    @Parameter(title: "Amount") var amount: String
    @Parameter(title: "Merchant") var merchant: String?
    @Parameter(title: "Card") var card: String?
    @Parameter(title: "Currency") var currency: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) spent at \(\.$merchant)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = ModelContainerFactory.makeContainer()
        let context = ModelContext(container)

        // Coordinate the write so a tap that fires while another process holds the store
        // doesn't clobber it. Idempotent dedupKey guards against double-fires.
        var thrown: Error?
        var message = "Logged to Budget"
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: ModelContainerFactory.storeURL, options: [], error: &coordinationError) { _ in
            do {
                let result = try TapLogger.log(rawAmount: amount, merchant: merchant,
                                               card: card, currency: currency, in: context)
                message = result.needsReview ? "\(result.message) — tap to review the category." : result.message
                // Re-check any budget threshold this expense may have crossed.
                BudgetAlerts.evaluate(in: context)
            } catch {
                thrown = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
