#if DEBUG
import Foundation
import SwiftData

/// DEBUG-only sample data for development / screenshots. Runs only when the app is launched
/// with `-seedDemo YES` (never in normal use), and only if the store is empty. Never shipped
/// behavior — production builds exclude this file entirely.
enum DemoSeed {
    static func seedIfRequested(_ context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "seedDemo") else { return }
        guard (try? context.fetchCount(FetchDescriptor<Bank>())) == 0 else { return }

        let kaspi = Bank(id: "kaspi.kz", name: "Kaspi", domain: "kaspi.kz", brandColorHex: "#F14635", sortOrder: 0)
        let freedom = Bank(id: "bankffin.kz", name: "Freedom", domain: "bankffin.kz", brandColorHex: "#51AF3D", sortOrder: 1)
        context.insert(kaspi); context.insert(freedom)
        let card = SubAccount(name: "Kaspi Gold", type: .card, currencyCode: "KZT", openingBalance: 250_000, sortOrder: 0)
        let deposit = SubAccount(name: "Freedom Deposit", type: .deposit, currencyCode: "KZT", openingBalance: 1_200_000, sortOrder: 0)
        card.bank = kaspi; deposit.bank = freedom
        context.insert(card); context.insert(deposit)
        try? context.save()

        try? Ledger.insert(TransactionDraft(kind: .income, amountOriginal: 600_000, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: card.id, categoryID: "salary", merchant: "Employer"), in: context)
        try? Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 12_500, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: card.id, categoryID: "groceries", merchant: "Small"), in: context)
        try? Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 3_200, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: card.id, categoryID: "food", merchant: "Bahandi"), in: context)

        context.insert(CategoryBudget(categoryID: "food", limitKZT: 40_000))
        context.insert(CategoryBudget(categoryID: "groceries", limitKZT: 120_000))
        try? context.save()
    }
}
#endif
