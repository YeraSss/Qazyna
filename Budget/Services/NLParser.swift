import Foundation
import SwiftData

/// The parsed result of a natural-language / OCR entry. Any field may be nil; the quick-add
/// UI fills the gaps. Shared output type for the heuristic parser and (when available) the
/// on-device Foundation Models parser, so the caller is agnostic to which produced it.
struct ParsedEntry {
    var amount: Decimal?
    var currencyCode: String?
    var kind: TransactionKind = .expense
    var categoryID: String?
    var accountID: UUID?
    var merchant: String?
}

/// On-device natural-language parser. The heuristic implementation always works (iOS 18+);
/// `parseSmart` upgrades to Apple's on-device Foundation Models when available (iOS 26 +
/// Apple-Intelligence-capable device) and falls back to the heuristic otherwise. Nothing
/// leaves the device in either path.
enum NLParser {

    /// Keyword → category slug hints for the heuristic parser.
    private static let keywordCategory: [String: String] = [
        "coffee": "food", "cafe": "food", "lunch": "food", "dinner": "food", "breakfast": "food",
        "restaurant": "food", "food": "food", "starbucks": "food", "mcdonald": "food", "pizza": "food",
        "grocery": "groceries", "groceries": "groceries", "supermarket": "groceries", "magnum": "groceries", "small": "groceries",
        "taxi": "transport", "uber": "transport", "yandex": "transport", "bus": "transport", "metro": "transport",
        "gas": "transport", "fuel": "transport", "petrol": "transport",
        "netflix": "subscriptions", "spotify": "subscriptions", "subscription": "subscriptions", "icloud": "subscriptions",
        "rent": "rent", "shopping": "shopping", "clothes": "shopping", "technodom": "shopping",
        "pharmacy": "health", "doctor": "health", "medicine": "health",
        "movie": "entertainment", "cinema": "entertainment", "game": "entertainment",
        "flight": "travel", "hotel": "travel", "ticket": "travel",
        "salary": "salary", "paycheck": "salary", "freelance": "freelance", "gift": "gift"
    ]
    private static let incomeWords: Set<String> = ["salary", "income", "paid", "received", "refund", "freelance", "bonus", "gift", "deposit", "paycheck"]
    private static let currencySymbols: [String: String] = ["$": "USD", "€": "EUR", "£": "GBP", "₸": "KZT", "₽": "RUB", "¥": "JPY"]
    private static let currencyWords: Set<String> = ["usd", "eur", "gbp", "kzt", "rub", "tenge", "dollars", "euros", "cny", "yuan"]

    /// Heuristic parse — deterministic, offline, instant.
    static func parseHeuristic(_ text: String, in context: ModelContext) -> ParsedEntry {
        var entry = ParsedEntry()
        let lower = text.lowercased()

        // Currency from symbol or word.
        for (sym, code) in currencySymbols where text.contains(sym) { entry.currencyCode = code }
        for word in lower.split(whereSeparator: { !$0.isLetter }) where currencyWords.contains(String(word)) {
            entry.currencyCode = normalizeCurrencyWord(String(word))
        }

        // Amount: first number-like run.
        if let range = lower.range(of: #"[0-9][0-9\s.,]*"#, options: .regularExpression) {
            let raw = String(lower[range])
            entry.amount = AmountParser.parse(raw, currencyCode: entry.currencyCode ?? Money.baseCurrency)
        }

        // Kind.
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        if !words.isDisjoint(with: incomeWords) { entry.kind = .income }

        // Category from keywords.
        for (kw, slug) in keywordCategory where lower.contains(kw) { entry.categoryID = slug; break }

        // Account by matching account or bank name tokens.
        let accounts = (try? context.fetch(FetchDescriptor<SubAccount>())) ?? []
        for acct in accounts {
            let name = acct.name.lowercased()
            let bank = (acct.bank?.name ?? "").lowercased()
            if (!name.isEmpty && lower.contains(name)) || (!bank.isEmpty && lower.contains(bank)) {
                entry.accountID = acct.id; break
            }
        }

        // Merchant / description: words that aren't numbers, currency, or the matched account.
        let merchant = text
            .replacingOccurrences(of: #"[0-9][0-9\s.,]*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !merchant.isEmpty { entry.merchant = merchant.capitalized }

        // Learned merchant mapping can override the keyword guess.
        if let m = entry.merchant, let learned = MerchantLearning.category(for: m, in: context) {
            entry.categoryID = learned
        }
        return entry
    }

    /// Uses Foundation Models when available, else the heuristic. The caller awaits this.
    static func parseSmart(_ text: String, in context: ModelContext) async -> ParsedEntry {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let smart = await FoundationModelsParser.parse(text, in: context) {
            return smart
        }
        #endif
        return parseHeuristic(text, in: context)
    }

    private static func normalizeCurrencyWord(_ w: String) -> String {
        switch w {
        case "tenge": return "KZT"
        case "dollars": return "USD"
        case "euros": return "EUR"
        case "yuan": return "CNY"
        default: return w.uppercased()
        }
    }
}
