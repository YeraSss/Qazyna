#if DEBUG
import Foundation
import SwiftData

/// DEBUG-only sample data for development / screenshots. Runs only when the app is launched
/// with `-seedDemo YES` (never in normal use), and only if the store is empty. Amounts are
/// **randomised** each fresh install — arbitrary opening balances, incomes, and expenses —
/// so it never looks like canned round numbers. Production builds exclude this file entirely.
enum DemoSeed {
    static func seedIfRequested(_ context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "seedDemo") else { return }
        guard (try? context.fetchCount(FetchDescriptor<Bank>())) == 0 else { return }

        // Banks + accounts with arbitrary opening balances.
        let kaspi = Bank(id: "kaspi.kz", name: "Kaspi", domain: "kaspi.kz", brandColorHex: "#F14635", sortOrder: 0)
        let freedom = Bank(id: "bankffin.kz", name: "Freedom", domain: "bankffin.kz", brandColorHex: "#51AF3D", sortOrder: 1)
        context.insert(kaspi); context.insert(freedom)

        let card = SubAccount(name: "Kaspi Gold", type: .card, currencyCode: "KZT",
                              openingBalance: Decimal(Int.random(in: 18_000...240_000)), sortOrder: 0)
        let deposit = SubAccount(name: "Freedom Deposit", type: .deposit, currencyCode: "KZT",
                                 openingBalance: Decimal(Int.random(in: 130_000...1_850_000)), sortOrder: 0)
        card.bank = kaspi; deposit.bank = freedom
        context.insert(card); context.insert(deposit)
        try? context.save()

        // 1–2 income entries with arbitrary amounts (no more fixed 600k salary).
        for _ in 0..<Int.random(in: 1...2) {
            let isSalary = Bool.random()
            try? Ledger.insert(TransactionDraft(
                kind: .income,
                amountOriginal: Decimal(Int.random(in: isSalary ? 213_000...947_000 : 35_000...260_000)),
                currencyCode: "KZT", fxRateToKZT: 1, date: randomRecentDate(),
                accountID: card.id, categoryID: isSalary ? "salary" : "freelance",
                merchant: isSalary ? ["Employer", "TOO Company"].randomElement()! : ["Upwork", "Client", "Kwork"].randomElement()!,
                source: .manual), in: context)
        }

        // A handful of random expenses on the card.
        let pools: [(cat: String, merchants: [String], range: ClosedRange<Int>)] = [
            ("food",          ["Bahandi", "Starbucks", "KFC", "Coffee Boom", "Del Papa"],   470...9_400),
            ("groceries",     ["Small", "Magnum", "Galmart", "Anvar"],                      1_350...37_800),
            ("transport",     ["Yandex Go", "InDrive", "Bus"],                              260...4_600),
            ("shopping",      ["Technodom", "Sulpak", "Zara", "Mechta"],                    3_900...108_500),
            ("entertainment", ["Kinopark", "Chaplin", "Steam"],                            1_150...14_700),
            ("subscriptions", ["Netflix", "Spotify", "iCloud", "YouTube"],                 890...6_450),
            ("health",        ["Europharma", "Sadykhan"],                                  1_450...21_300),
            ("bills",         ["Beeline", "Almaty Su", "Kazakhtelecom"],                   2_800...27_600)
        ]
        for _ in 0..<Int.random(in: 9...16) {
            let pick = pools.randomElement()!
            try? Ledger.insert(TransactionDraft(
                kind: .expense, amountOriginal: Decimal(Int.random(in: pick.range)),
                currencyCode: "KZT", fxRateToKZT: 1, date: randomRecentDate(),
                accountID: card.id, categoryID: pick.cat, merchant: pick.merchants.randomElement()!,
                note: ["Online", "In store", "Family", nil, nil].randomElement()!,
                source: .manual), in: context)
        }

        // A Tap-to-Track capture awaiting review (uncategorized), to demo the Review inbox.
        try? Ledger.insert(TransactionDraft(
            kind: .expense, amountOriginal: Decimal(Int.random(in: 900...12_000)),
            currencyCode: "KZT", fxRateToKZT: 1, date: randomRecentDate(),
            accountID: card.id, categoryID: "other",
            merchant: ["Magnum", "Wolt", "Glovo", "Arbuz"].randomElement()!,
            source: .tapToTrack, needsReview: true), in: context)

        // Arbitrary budgets so the Budgets/Analytics screens have data.
        context.insert(CategoryBudget(categoryID: "food", limitKZT: Decimal(Int.random(in: 24_000...62_000))))
        context.insert(CategoryBudget(categoryID: "groceries", limitKZT: Decimal(Int.random(in: 55_000...155_000))))
        try? context.save()
    }

    /// A random moment within the last ~2 weeks.
    private static func randomRecentDate() -> Date {
        Date().addingTimeInterval(-Double.random(in: 0...(14 * 86_400)))
    }
}
#endif
