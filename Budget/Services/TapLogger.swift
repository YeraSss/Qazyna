import Foundation
import SwiftData

/// Turns a raw Apple Pay tap (from the Shortcuts automation) into a logged transaction.
/// Kept separate from the App Intent so it's unit-testable and reusable.
///
/// Resolution rules:
///  • account  ← CardMapping[card] → else the first card account → else first account
///  • currency ← explicit → card mapping default → KZT
///  • category ← learned MerchantMapping[merchant] → else "other" (flagged needsReview)
///  • amount   ← AmountParser (locale-tolerant, currency-aware)
///  • dedupKey ← deterministic, so a double-firing automation cannot create a duplicate
enum TapLogger {

    struct Result { let transaction: TransactionRecord; let needsReview: Bool; let message: String }

    enum TapError: Error, CustomStringConvertible {
        case noAccounts, badAmount
        var description: String {
            switch self {
            case .noAccounts: return "No accounts set up yet."
            case .badAmount:  return "Couldn't read the amount."
            }
        }
    }

    struct Preview { let accountName: String; let categoryID: String; let amount: Decimal; let currency: String; let mappingMatched: Bool }

    /// Resolve a hypothetical tap WITHOUT writing anything — used by the in-app "test capture"
    /// so the user can confirm the app side + card mapping work, isolating any failure to the
    /// device-side Shortcuts automation.
    static func preview(rawAmount: String, merchant: String?, card: String?, currency: String?,
                        in context: ModelContext) -> Preview? {
        let accounts = (try? context.fetch(FetchDescriptor<SubAccount>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        guard !accounts.isEmpty else { return nil }
        var account = accounts.first { $0.type == .card } ?? accounts[0]
        var mappingMatched = false
        var resolvedCurrency = currency?.uppercased()
        if let card, !card.isEmpty {
            let key = CardMapping.normalize(card)
            var d = FetchDescriptor<CardMapping>(predicate: #Predicate { $0.cardKey == key }); d.fetchLimit = 1
            if let m = try? context.fetch(d).first, let acct = accounts.first(where: { $0.id == m.accountID }) {
                account = acct; mappingMatched = true
                if resolvedCurrency == nil { resolvedCurrency = m.defaultCurrencyCode }
            }
        }
        let cur = (resolvedCurrency == account.currencyCode ? resolvedCurrency : nil) ?? account.currencyCode
        guard let amount = AmountParser.parse(rawAmount, currencyCode: cur) else { return nil }
        let categoryID = merchant.flatMap { MerchantLearning.category(for: $0, in: context) } ?? "other"
        return Preview(accountName: "\(account.bank?.name ?? "") \(account.name)", categoryID: categoryID,
                       amount: amount, currency: cur, mappingMatched: mappingMatched)
    }

    @discardableResult
    static func log(rawAmount: String, merchant: String?, card: String?, currency: String?,
                    date: Date = .now, in context: ModelContext) throws -> Result {
        let accounts = try context.fetch(FetchDescriptor<SubAccount>(sortBy: [SortDescriptor(\.sortOrder)]))
        guard !accounts.isEmpty else { throw TapError.noAccounts }

        // Account + default currency from the card mapping.
        var mappingMatched = false
        var account: SubAccount = accounts.first { $0.type == .card } ?? accounts[0]
        var resolvedCurrency = currency?.uppercased()
        if let card, !card.isEmpty {
            let key = CardMapping.normalize(card)
            var d = FetchDescriptor<CardMapping>(predicate: #Predicate { $0.cardKey == key }); d.fetchLimit = 1
            if let mapping = try? context.fetch(d).first,
               let acct = accounts.first(where: { $0.id == mapping.accountID }) {
                account = acct
                mappingMatched = true
                if resolvedCurrency == nil { resolvedCurrency = mapping.defaultCurrencyCode }
            }
        }
        // The transaction currency must match the account currency; fall back to it.
        let cur = (resolvedCurrency ?? account.currencyCode)
        let currencyForAccount = (cur == account.currencyCode) ? cur : account.currencyCode

        guard let amount = AmountParser.parse(rawAmount, currencyCode: currencyForAccount), amount > 0 else {
            throw TapError.badAmount
        }

        // Category: learned mapping or fall back to "other".
        let learned = merchant.flatMap { MerchantLearning.category(for: $0, in: context) }
        let categoryID = learned ?? "other"
        // Review needed if we had to guess the account or the category.
        let needsReview = !mappingMatched || learned == nil

        let rate = RateSnapshot.loadCurrent().rateToKZT(currencyForAccount)
        let dayKey = DateKeys.dayKey(date)
        let merchantKey = merchant.map(MerchantMapping.normalize) ?? "unknown"
        let dedupKey = "tap-\(CardMapping.normalize(card ?? "none"))-\(dayKey)-\(amount)-\(merchantKey)"

        let draft = TransactionDraft(
            dedupKey: dedupKey, kind: .expense, amountOriginal: amount,
            currencyCode: currencyForAccount, fxRateToKZT: rate, date: date,
            accountID: account.id, categoryID: categoryID,
            merchant: merchant, source: .tapToTrack, needsReview: needsReview
        )
        let tx = try Ledger.insert(draft, in: context)
        let msg = "Logged \(CurrencyFormatter.string(amount, currencyCode: currencyForAccount)) at \(merchant ?? "merchant")"
        return Result(transaction: tx, needsReview: needsReview, message: msg)
    }
}
