import Foundation
import SwiftData

/// CSV/JSON backup and import. Export produces a human-readable CSV of transactions and a
/// full JSON backup (banks, accounts, categories, transactions, transfers, budgets, goals,
/// recurring). Import supports appending transactions from a CSV and restoring a JSON backup.
enum ImportExportService {

    // MARK: - CSV export (transactions)

    static func transactionsCSV(in context: ModelContext) -> String {
        let txs = (try? context.fetch(FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let cats = Dictionary(((try? context.fetch(FetchDescriptor<Category>())) ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let accts = Dictionary(((try? context.fetch(FetchDescriptor<SubAccount>())) ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let df = ISO8601DateFormatter()
        var rows = ["date,kind,amount,currency,amountKZT,category,account,merchant,note"]
        for t in txs {
            let cols = [
                df.string(from: t.date), t.kind.rawValue,
                NSDecimalNumber(decimal: t.amountOriginal).stringValue, t.currencyCode,
                NSDecimalNumber(decimal: t.amountKZT).stringValue,
                cats[t.categoryID] ?? t.categoryID, accts[t.accountID] ?? "",
                t.merchant ?? "", t.note ?? ""
            ].map(escape)
            rows.append(cols.joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func escape(_ s: String) -> String {
        (s.contains(",") || s.contains("\"") || s.contains("\n"))
            ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
    }

    // MARK: - JSON backup

    struct Backup: Codable {
        var version = 2
        var banks: [BankDTO] = []
        var accounts: [AccountDTO] = []
        var categories: [CategoryDTO] = []
        var transactions: [TxDTO] = []
        var transfers: [TransferDTO] = []
        var budgets: [BudgetDTO] = []
        var goals: [GoalDTO] = []
        var recurring: [RecurringDTO] = []
        var adjustments: [AdjustmentDTO] = []
        var merchantMappings: [MerchantDTO] = []
        var cardMappings: [CardDTO] = []

        init() {}

        /// Tolerant decode: older backups that lack newer arrays still restore (missing → []).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            banks = try c.decodeIfPresent([BankDTO].self, forKey: .banks) ?? []
            accounts = try c.decodeIfPresent([AccountDTO].self, forKey: .accounts) ?? []
            categories = try c.decodeIfPresent([CategoryDTO].self, forKey: .categories) ?? []
            transactions = try c.decodeIfPresent([TxDTO].self, forKey: .transactions) ?? []
            transfers = try c.decodeIfPresent([TransferDTO].self, forKey: .transfers) ?? []
            budgets = try c.decodeIfPresent([BudgetDTO].self, forKey: .budgets) ?? []
            goals = try c.decodeIfPresent([GoalDTO].self, forKey: .goals) ?? []
            recurring = try c.decodeIfPresent([RecurringDTO].self, forKey: .recurring) ?? []
            adjustments = try c.decodeIfPresent([AdjustmentDTO].self, forKey: .adjustments) ?? []
            merchantMappings = try c.decodeIfPresent([MerchantDTO].self, forKey: .merchantMappings) ?? []
            cardMappings = try c.decodeIfPresent([CardDTO].self, forKey: .cardMappings) ?? []
        }
    }
    // Fields added after v1 are Optional so older backups decode without error.
    struct BankDTO: Codable { var id, name, domain, brandColorHex: String; var logoCacheKey: String?; var sortOrder: Int; var createdAt: Date? }
    struct AdjustmentDTO: Codable { var id: UUID; var accountID: UUID; var delta: Decimal; var reason: String?; var date: Date; var createdAt: Date? }
    struct AccountDTO: Codable { var id: UUID; var name, type, currencyCode: String; var openingBalance: Decimal; var bankID: String?; var includeInNetWorth: Bool; var sortOrder: Int; var isArchived: Bool?; var openingBalanceDate: Date?; var createdAt: Date? }
    struct CategoryDTO: Codable { var id, name, emoji, colorHex, kind: String; var sortOrder: Int; var isArchived: Bool?; var createdAt: Date? }
    struct TxDTO: Codable { var id: UUID; var dedupKey, kind: String; var amountOriginal, fxRateToKZT: Decimal; var currencyCode: String; var date: Date; var accountID: UUID; var categoryID: String; var merchant, note, source: String?; var needsReview: Bool?; var createdAt: Date? }
    struct TransferDTO: Codable { var id: UUID; var fromAccountID, toAccountID: UUID; var fromAmount, toAmount: Decimal; var fromCurrencyCode, toCurrencyCode: String; var date: Date; var note: String?; var dedupKey: String?; var createdAt: Date? }
    struct BudgetDTO: Codable { var categoryID: String; var limitKZT: Decimal; var thresholds: [Double]; var id: UUID?; var createdAt: Date? }
    struct GoalDTO: Codable { var id: UUID; var name: String; var targetKZT: Decimal; var linkedAccountID: UUID?; var manualSavedKZT: Decimal; var targetDate: Date?; var createdAt: Date? }
    struct RecurringDTO: Codable { var id: UUID; var title, kind: String; var amountOriginal: Decimal; var currencyCode: String; var accountID: UUID; var categoryID: String; var note: String?; var frequency: String; var intervalDays: Int?; var nextRun: Date; var autoLog: Bool; var isActive: Bool?; var lastRun: Date?; var createdAt: Date? }
    struct MerchantDTO: Codable { var merchantKey, displayMerchant, categoryID: String; var hitCount: Int; var updatedAt: Date? }
    struct CardDTO: Codable { var cardKey, displayCardName: String; var accountID: UUID; var defaultCurrencyCode: String; var createdAt: Date? }

    static func exportBackup(in context: ModelContext) -> Data? {
        var b = Backup()
        b.banks = ((try? context.fetch(FetchDescriptor<Bank>())) ?? []).map { BankDTO(id: $0.id, name: $0.name, domain: $0.domain, brandColorHex: $0.brandColorHex, logoCacheKey: $0.logoCacheKey, sortOrder: $0.sortOrder, createdAt: $0.createdAt) }
        b.accounts = ((try? context.fetch(FetchDescriptor<SubAccount>())) ?? []).map { AccountDTO(id: $0.id, name: $0.name, type: $0.typeRaw, currencyCode: $0.currencyCode, openingBalance: $0.openingBalance, bankID: $0.bank?.id, includeInNetWorth: $0.includeInNetWorth, sortOrder: $0.sortOrder, isArchived: $0.isArchived, openingBalanceDate: $0.openingBalanceDate, createdAt: $0.createdAt) }
        b.categories = ((try? context.fetch(FetchDescriptor<Category>())) ?? []).map { CategoryDTO(id: $0.id, name: $0.name, emoji: $0.emoji, colorHex: $0.colorHex, kind: $0.kindRaw, sortOrder: $0.sortOrder, isArchived: $0.isArchived, createdAt: $0.createdAt) }
        b.transactions = ((try? context.fetch(FetchDescriptor<TransactionRecord>())) ?? []).map { TxDTO(id: $0.id, dedupKey: $0.dedupKey, kind: $0.kindRaw, amountOriginal: $0.amountOriginal, fxRateToKZT: $0.fxRateToKZT, currencyCode: $0.currencyCode, date: $0.date, accountID: $0.accountID, categoryID: $0.categoryID, merchant: $0.merchant, note: $0.note, source: $0.sourceRaw, needsReview: $0.needsReview, createdAt: $0.createdAt) }
        b.transfers = ((try? context.fetch(FetchDescriptor<TransferRecord>())) ?? []).map { TransferDTO(id: $0.id, fromAccountID: $0.fromAccountID, toAccountID: $0.toAccountID, fromAmount: $0.fromAmount, toAmount: $0.toAmount, fromCurrencyCode: $0.fromCurrencyCode, toCurrencyCode: $0.toCurrencyCode, date: $0.date, note: $0.note, dedupKey: $0.dedupKey, createdAt: $0.createdAt) }
        b.budgets = ((try? context.fetch(FetchDescriptor<CategoryBudget>())) ?? []).map { BudgetDTO(categoryID: $0.categoryID, limitKZT: $0.limitKZT, thresholds: $0.thresholds, id: $0.id, createdAt: $0.createdAt) }
        b.goals = ((try? context.fetch(FetchDescriptor<SavingsGoal>())) ?? []).map { GoalDTO(id: $0.id, name: $0.name, targetKZT: $0.targetKZT, linkedAccountID: $0.linkedAccountID, manualSavedKZT: $0.manualSavedKZT, targetDate: $0.targetDate, createdAt: $0.createdAt) }
        b.recurring = ((try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []).map { RecurringDTO(id: $0.id, title: $0.title, kind: $0.kindRaw, amountOriginal: $0.amountOriginal, currencyCode: $0.currencyCode, accountID: $0.accountID, categoryID: $0.categoryID, note: $0.note, frequency: $0.frequencyRaw, intervalDays: $0.intervalDays, nextRun: $0.nextRun, autoLog: $0.autoLog, isActive: $0.isActive, lastRun: $0.lastRun, createdAt: $0.createdAt) }
        b.adjustments = ((try? context.fetch(FetchDescriptor<BalanceAdjustment>())) ?? []).map { AdjustmentDTO(id: $0.id, accountID: $0.accountID, delta: $0.delta, reason: $0.reason, date: $0.date, createdAt: $0.createdAt) }
        b.merchantMappings = ((try? context.fetch(FetchDescriptor<MerchantMapping>())) ?? []).map { MerchantDTO(merchantKey: $0.merchantKey, displayMerchant: $0.displayMerchant, categoryID: $0.categoryID, hitCount: $0.hitCount, updatedAt: $0.updatedAt) }
        b.cardMappings = ((try? context.fetch(FetchDescriptor<CardMapping>())) ?? []).map { CardDTO(cardKey: $0.cardKey, displayCardName: $0.displayCardName, accountID: $0.accountID, defaultCurrencyCode: $0.defaultCurrencyCode, createdAt: $0.createdAt) }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(b)
    }

    /// Restore a JSON backup: wipes existing data, re-inserts, then rebuilds derived state.
    static func restoreBackup(_ data: Data, in context: ModelContext) throws {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let b = try dec.decode(Backup.self, from: data)

        // Wipe existing data explicitly per-type so it can never silently leave stray rows
        // (e.g. default categories seeded on first launch, or data added before restoring).
        try context.delete(model: TransactionRecord.self)
        try context.delete(model: TransferRecord.self)
        try context.delete(model: BalanceAdjustment.self)
        try context.delete(model: DailyRollup.self)
        try context.delete(model: MonthlyRollup.self)
        try context.delete(model: CategoryMonthlyRollup.self)
        try context.delete(model: NetWorthSnapshot.self)
        try context.delete(model: CategoryBudget.self)
        try context.delete(model: SavingsGoal.self)
        try context.delete(model: RecurringRule.self)
        try context.delete(model: MerchantMapping.self)
        try context.delete(model: CardMapping.self)
        try context.delete(model: SubAccount.self)
        try context.delete(model: Bank.self)
        try context.delete(model: Category.self)
        try context.save()

        var bankByID: [String: Bank] = [:]
        for d in b.banks {
            let bank = Bank(id: d.id, name: d.name, domain: d.domain, brandColorHex: d.brandColorHex,
                            logoCacheKey: d.logoCacheKey, sortOrder: d.sortOrder, createdAt: d.createdAt ?? .now)
            context.insert(bank); bankByID[d.id] = bank
        }
        var accountByID: [UUID: SubAccount] = [:]
        for d in b.accounts {
            let acct = SubAccount(id: d.id, name: d.name, type: AccountType(rawValue: d.type) ?? .cash,
                                  currencyCode: d.currencyCode, openingBalance: d.openingBalance,
                                  openingBalanceDate: d.openingBalanceDate ?? .now,
                                  includeInNetWorth: d.includeInNetWorth, isArchived: d.isArchived ?? false,
                                  sortOrder: d.sortOrder, createdAt: d.createdAt ?? .now)
            if let bid = d.bankID { acct.bank = bankByID[bid] }
            context.insert(acct); accountByID[d.id] = acct
        }
        for d in b.categories {
            context.insert(Category(id: d.id, name: d.name, emoji: d.emoji, colorHex: d.colorHex,
                                    kind: TransactionKind(rawValue: d.kind) ?? .expense, sortOrder: d.sortOrder,
                                    isArchived: d.isArchived ?? false, createdAt: d.createdAt ?? .now))
        }
        for d in b.transactions {
            let tx = TransactionRecord(id: d.id, dedupKey: d.dedupKey, kind: TransactionKind(rawValue: d.kind) ?? .expense,
                amountOriginal: d.amountOriginal, currencyCode: d.currencyCode, fxRateToKZT: d.fxRateToKZT,
                date: d.date, accountID: d.accountID, categoryID: d.categoryID, merchant: d.merchant, note: d.note,
                source: EntrySource(rawValue: d.source ?? "manual") ?? .manual,
                needsReview: d.needsReview ?? false, createdAt: d.createdAt ?? .now)
            tx.account = accountByID[d.accountID]   // reconnect relationship (keeps cascade-delete working)
            context.insert(tx)
        }
        for d in b.transfers {
            context.insert(TransferRecord(id: d.id, dedupKey: d.dedupKey ?? UUID().uuidString,
                fromAccountID: d.fromAccountID, toAccountID: d.toAccountID,
                fromAmount: d.fromAmount, fromCurrencyCode: d.fromCurrencyCode, toAmount: d.toAmount,
                toCurrencyCode: d.toCurrencyCode, date: d.date, note: d.note, createdAt: d.createdAt ?? .now))
        }
        for d in b.budgets { context.insert(CategoryBudget(id: d.id ?? UUID(), categoryID: d.categoryID, limitKZT: d.limitKZT, thresholds: d.thresholds, createdAt: d.createdAt ?? .now)) }
        for d in b.goals { context.insert(SavingsGoal(id: d.id, name: d.name, targetKZT: d.targetKZT, linkedAccountID: d.linkedAccountID, manualSavedKZT: d.manualSavedKZT, targetDate: d.targetDate, createdAt: d.createdAt ?? .now)) }
        for d in b.recurring {
            let rule = RecurringRule(id: d.id, title: d.title, kind: TransactionKind(rawValue: d.kind) ?? .expense,
                amountOriginal: d.amountOriginal, currencyCode: d.currencyCode, accountID: d.accountID, categoryID: d.categoryID,
                note: d.note, frequency: RecurrenceFrequency(rawValue: d.frequency) ?? .monthly, intervalDays: d.intervalDays,
                nextRun: d.nextRun, autoLog: d.autoLog, isActive: d.isActive ?? true, createdAt: d.createdAt ?? .now)
            rule.lastRun = d.lastRun
            context.insert(rule)
        }
        // Manual balance adjustments must be restored BEFORE rebuildBalances, or every
        // account whose balance was corrected would revert to opening + transactions only.
        for d in b.adjustments {
            context.insert(BalanceAdjustment(id: d.id, accountID: d.accountID, delta: d.delta, reason: d.reason, date: d.date, createdAt: d.createdAt ?? .now))
        }
        for d in b.merchantMappings {
            context.insert(MerchantMapping(merchantKey: d.merchantKey, displayMerchant: d.displayMerchant, categoryID: d.categoryID, hitCount: d.hitCount, updatedAt: d.updatedAt ?? .now))
        }
        for d in b.cardMappings {
            context.insert(CardMapping(cardKey: d.cardKey, displayCardName: d.displayCardName, accountID: d.accountID, defaultCurrencyCode: d.defaultCurrencyCode, createdAt: d.createdAt ?? .now))
        }
        try context.save()
        try Ledger.rebuildBalances(in: context)
        try Ledger.rebuildRollups(in: context)
    }

    // MARK: - CSV import (append transactions)

    /// Parse CSV text into rows of fields (handles quoted fields).
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []; var field = ""; var row: [String] = []; var inQuotes = false
        var iterator = text.makeIterator(); var pending: Character?
        func next() -> Character? { if let p = pending { pending = nil; return p }; return iterator.next() }
        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let n = next() { if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n } }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                case "\r": break
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    struct CSVMapping { var date, amount, merchant, category, note: Int?; var kind: Int? }

    /// Import mapped CSV rows (excluding header) into `account`. Returns count imported.
    @discardableResult
    static func importCSV(rows: [[String]], mapping: CSVMapping, into account: SubAccount,
                          fxRate: Decimal, in context: ModelContext) -> Int {
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let catByName = Dictionary(categories.map { ($0.name.lowercased(), $0.id) }, uniquingKeysWith: { a, _ in a })
        var imported = 0
        for (i, row) in rows.enumerated() {
            func col(_ idx: Int?) -> String? { guard let idx, idx < row.count else { return nil }; return row[idx] }
            guard let amtStr = col(mapping.amount),
                  let amount = AmountParser.parse(amtStr, currencyCode: account.currencyCode), amount > 0 else { continue }
            let date = col(mapping.date).flatMap(parseDate) ?? Date()
            let kind: TransactionKind = (col(mapping.kind)?.lowercased().contains("income") ?? false) ? .income : .expense
            let catName = col(mapping.category)?.lowercased() ?? ""
            let categoryID = catByName[catName] ?? (kind == .income ? "income_other" : "other")
            let merchant = col(mapping.merchant)
            let dedupKey = "csv-\(account.id.uuidString)-\(i)-\(DateKeys.dayKey(date))-\(amount)"
            let draft = TransactionDraft(dedupKey: dedupKey, kind: kind, amountOriginal: amount,
                currencyCode: account.currencyCode, fxRateToKZT: fxRate, date: date, accountID: account.id,
                categoryID: categoryID, merchant: merchant, note: col(mapping.note), source: .csvImport)
            if (try? Ledger.insert(draft, in: context)) != nil { imported += 1 }
        }
        return imported
    }

    private static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter(); if let d = iso.date(from: s) { return d }
        let formats = ["yyyy-MM-dd", "dd.MM.yyyy", "MM/dd/yyyy", "dd/MM/yyyy", "yyyy/MM/dd"]
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
        return nil
    }
}
