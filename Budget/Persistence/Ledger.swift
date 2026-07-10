import Foundation
import SwiftData

/// The **single write chokepoint** for all money mutations. Every caller — manual entry,
/// Tap-to-Track, import, recurring — funnels through here so the two invariants hold:
///
///  1. `account.cachedBalance == openingBalance + Σ ledger deltas`
///  2. rollups == recompute(ledger)     (rollups are a derived cache, never truth)
///
/// Each public method performs its mutation **and** the matching balance/rollup deltas in
/// one `context.save()` (atomic). Edits use reverse-then-repost so changing an amount, date,
/// category, account, or currency stays consistent. `rebuildRollups` / `rebuildBalances` /
/// `integrityCheck` are the recovery net (also used after bulk import/restore).
enum Ledger {

    enum LedgerError: Error { case accountNotFound }

    // MARK: - Transactions

    @discardableResult
    static func insert(_ draft: TransactionDraft, in context: ModelContext) throws -> TransactionRecord {
        // Idempotency: if a row with this dedupKey already exists, return it untouched.
        // (SwiftData upserts on a `.unique` conflict rather than throwing, so we must check
        // explicitly — otherwise a re-fired tap / re-run import would double-count.)
        if let key = draft.dedupKey {
            var d = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.dedupKey == key })
            d.fetchLimit = 1
            if let existing = try? context.fetch(d).first { return existing }
        }
        let tx = TransactionRecord(
            id: draft.id ?? UUID(),
            dedupKey: draft.dedupKey ?? UUID().uuidString,
            kind: draft.kind,
            amountOriginal: draft.amountOriginal,
            currencyCode: draft.currencyCode,
            fxRateToKZT: draft.fxRateToKZT,
            date: draft.date,
            accountID: draft.accountID,
            categoryID: draft.categoryID,
            merchant: draft.merchant,
            note: draft.note,
            source: draft.source,
            needsReview: draft.needsReview
        )
        tx.account = try account(draft.accountID, in: context)
        context.insert(tx)
        apply(tx, sign: 1, in: context)
        try context.save()
        return tx
    }

    /// Apply a full edit: reverse the old contribution, mutate, repost the new one.
    static func update(_ tx: TransactionRecord, with draft: TransactionDraft, in context: ModelContext) throws {
        apply(tx, sign: -1, in: context)            // reverse using OLD values

        tx.kind = draft.kind
        tx.amountOriginal = draft.amountOriginal
        tx.currencyCode = draft.currencyCode
        tx.fxRateToKZT = draft.fxRateToKZT
        tx.amountKZT = Money.roundedKZT(draft.amountOriginal * draft.fxRateToKZT)
        tx.date = draft.date
        tx.dateKey = DateKeys.dayKey(draft.date)
        tx.monthKey = DateKeys.monthKey(draft.date)
        tx.accountID = draft.accountID
        tx.categoryID = draft.categoryID
        tx.merchant = draft.merchant
        tx.note = draft.note
        tx.needsReview = draft.needsReview
        tx.account = try account(draft.accountID, in: context)

        apply(tx, sign: 1, in: context)             // repost using NEW values
        try context.save()
    }

    static func delete(_ tx: TransactionRecord, in context: ModelContext) throws {
        apply(tx, sign: -1, in: context)
        context.delete(tx)
        try context.save()
    }

    /// Set only the category (used when the user corrects a `needsReview` tap) — cheap path.
    static func recategorize(_ tx: TransactionRecord, to categoryID: String, in context: ModelContext) throws {
        guard tx.categoryID != categoryID else {
            tx.needsReview = false
            try context.save()
            return
        }
        removeCategoryContribution(tx, in: context)
        tx.categoryID = categoryID
        addCategoryContribution(tx, in: context)
        tx.needsReview = false
        try context.save()
    }

    // MARK: - Transfers

    @discardableResult
    static func transfer(_ draft: TransferDraft, in context: ModelContext) throws -> TransferRecord {
        let from = try account(draft.fromAccountID, in: context)
        let to = try account(draft.toAccountID, in: context)
        from.cachedBalance -= draft.fromAmount
        to.cachedBalance += draft.toAmount
        let record = TransferRecord(
            fromAccountID: draft.fromAccountID,
            toAccountID: draft.toAccountID,
            fromAmount: draft.fromAmount,
            fromCurrencyCode: draft.fromCurrencyCode,
            toAmount: draft.toAmount,
            toCurrencyCode: draft.toCurrencyCode,
            date: draft.date,
            note: draft.note
        )
        context.insert(record)
        try context.save()
        return record
    }

    static func deleteTransfer(_ record: TransferRecord, in context: ModelContext) throws {
        if let from = try? account(record.fromAccountID, in: context) { from.cachedBalance += record.fromAmount }
        if let to = try? account(record.toAccountID, in: context) { to.cachedBalance -= record.toAmount }
        context.delete(record)
        try context.save()
    }

    // MARK: - Manual balance adjustment (writes an explicit ledger entry, never overwrites)

    static func adjustBalance(_ account: SubAccount, to target: Decimal, reason: String?, in context: ModelContext) throws {
        let delta = target - account.cachedBalance
        guard delta != 0 else { return }
        let adj = BalanceAdjustment(accountID: account.id, delta: delta, reason: reason)
        context.insert(adj)
        account.cachedBalance += delta
        try context.save()
    }

    // MARK: - Contribution application

    /// Add (sign +1) or remove (sign -1) a transaction's contribution to the account balance
    /// and the KZT rollups, based on the transaction's CURRENT field values.
    private static func apply(_ tx: TransactionRecord, sign: Int, in context: ModelContext) {
        // Balance (account currency)
        if let acct = try? account(tx.accountID, in: context) {
            acct.cachedBalance += tx.signedAmountOriginal * Decimal(sign)
        }
        // Rollups (KZT)
        let amt = tx.amountKZT * Decimal(sign)
        let isExpense = tx.kind == .expense
        let daily = fetchOrCreateDaily(dayKey: tx.dateKey, monthKey: tx.monthKey, in: context)
        let monthly = fetchOrCreateMonthly(monthKey: tx.monthKey, in: context)
        let catMonthly = fetchOrCreateCategoryMonthly(monthKey: tx.monthKey, categoryID: tx.categoryID, in: context)
        if isExpense {
            daily.expenseKZT += amt; monthly.expenseKZT += amt; catMonthly.expenseKZT += amt
        } else {
            daily.incomeKZT += amt; monthly.incomeKZT += amt; catMonthly.incomeKZT += amt
        }
        tx.rolledUp = sign > 0
    }

    private static func removeCategoryContribution(_ tx: TransactionRecord, in context: ModelContext) {
        let cat = fetchOrCreateCategoryMonthly(monthKey: tx.monthKey, categoryID: tx.categoryID, in: context)
        if tx.kind == .expense { cat.expenseKZT -= tx.amountKZT } else { cat.incomeKZT -= tx.amountKZT }
    }
    private static func addCategoryContribution(_ tx: TransactionRecord, in context: ModelContext) {
        let cat = fetchOrCreateCategoryMonthly(monthKey: tx.monthKey, categoryID: tx.categoryID, in: context)
        if tx.kind == .expense { cat.expenseKZT += tx.amountKZT } else { cat.incomeKZT += tx.amountKZT }
    }

    // MARK: - Fetch helpers

    static func account(_ id: UUID, in context: ModelContext) throws -> SubAccount {
        let target = id
        var d = FetchDescriptor<SubAccount>(predicate: #Predicate { $0.id == target })
        d.fetchLimit = 1
        guard let acct = try context.fetch(d).first else { throw LedgerError.accountNotFound }
        return acct
    }

    private static func fetchOrCreateDaily(dayKey: Int, monthKey: Int, in context: ModelContext) -> DailyRollup {
        let key = dayKey
        var d = FetchDescriptor<DailyRollup>(predicate: #Predicate { $0.dayKey == key })
        d.fetchLimit = 1
        if let row = try? context.fetch(d).first { return row }
        let row = DailyRollup(dayKey: dayKey, monthKey: monthKey)
        context.insert(row)
        return row
    }

    private static func fetchOrCreateMonthly(monthKey: Int, in context: ModelContext) -> MonthlyRollup {
        let key = monthKey
        var d = FetchDescriptor<MonthlyRollup>(predicate: #Predicate { $0.monthKey == key })
        d.fetchLimit = 1
        if let row = try? context.fetch(d).first { return row }
        let row = MonthlyRollup(monthKey: monthKey)
        context.insert(row)
        return row
    }

    private static func fetchOrCreateCategoryMonthly(monthKey: Int, categoryID: String, in context: ModelContext) -> CategoryMonthlyRollup {
        let composite = CategoryMonthlyRollup.key(monthKey: monthKey, categoryID: categoryID)
        var d = FetchDescriptor<CategoryMonthlyRollup>(predicate: #Predicate { $0.key == composite })
        d.fetchLimit = 1
        if let row = try? context.fetch(d).first { return row }
        let row = CategoryMonthlyRollup(monthKey: monthKey, categoryID: categoryID)
        context.insert(row)
        return row
    }

    // MARK: - Recovery net

    /// Recompute every rollup from the transaction ledger.
    static func rebuildRollups(in context: ModelContext) throws {
        for row in (try? context.fetch(FetchDescriptor<DailyRollup>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<MonthlyRollup>())) ?? [] { context.delete(row) }
        for row in (try? context.fetch(FetchDescriptor<CategoryMonthlyRollup>())) ?? [] { context.delete(row) }
        let txs = try context.fetch(FetchDescriptor<TransactionRecord>())
        for tx in txs {
            let amt = tx.amountKZT
            let daily = fetchOrCreateDaily(dayKey: tx.dateKey, monthKey: tx.monthKey, in: context)
            let monthly = fetchOrCreateMonthly(monthKey: tx.monthKey, in: context)
            let cat = fetchOrCreateCategoryMonthly(monthKey: tx.monthKey, categoryID: tx.categoryID, in: context)
            if tx.kind == .expense {
                daily.expenseKZT += amt; monthly.expenseKZT += amt; cat.expenseKZT += amt
            } else {
                daily.incomeKZT += amt; monthly.incomeKZT += amt; cat.incomeKZT += amt
            }
            tx.rolledUp = true
        }
        try context.save()
    }

    /// Recompute every account balance from opening balance + ledger.
    static func rebuildBalances(in context: ModelContext) throws {
        let accounts = try context.fetch(FetchDescriptor<SubAccount>())
        let txs = try context.fetch(FetchDescriptor<TransactionRecord>())
        let adjustments = try context.fetch(FetchDescriptor<BalanceAdjustment>())
        let transfers = try context.fetch(FetchDescriptor<TransferRecord>())
        for acct in accounts {
            var balance = acct.openingBalance
            for tx in txs where tx.accountID == acct.id { balance += tx.signedAmountOriginal }
            for adj in adjustments where adj.accountID == acct.id { balance += adj.delta }
            for t in transfers where t.fromAccountID == acct.id { balance -= t.fromAmount }
            for t in transfers where t.toAccountID == acct.id { balance += t.toAmount }
            acct.cachedBalance = balance
        }
        try context.save()
    }

    /// Returns true if rollups + balances already match a fresh recompute (used by tests / debug).
    static func integrityCheck(in context: ModelContext) -> Bool {
        guard let accounts = try? context.fetch(FetchDescriptor<SubAccount>()),
              let txs = try? context.fetch(FetchDescriptor<TransactionRecord>()),
              let adjustments = try? context.fetch(FetchDescriptor<BalanceAdjustment>()),
              let transfers = try? context.fetch(FetchDescriptor<TransferRecord>()),
              let monthlies = try? context.fetch(FetchDescriptor<MonthlyRollup>()) else { return false }

        for acct in accounts {
            var balance = acct.openingBalance
            for tx in txs where tx.accountID == acct.id { balance += tx.signedAmountOriginal }
            for adj in adjustments where adj.accountID == acct.id { balance += adj.delta }
            for t in transfers where t.fromAccountID == acct.id { balance -= t.fromAmount }
            for t in transfers where t.toAccountID == acct.id { balance += t.toAmount }
            if balance != acct.cachedBalance { return false }
        }

        var expByMonth: [Int: Decimal] = [:]
        var incByMonth: [Int: Decimal] = [:]
        for tx in txs {
            if tx.kind == .expense { expByMonth[tx.monthKey, default: 0] += tx.amountKZT }
            else { incByMonth[tx.monthKey, default: 0] += tx.amountKZT }
        }
        for m in monthlies {
            if m.expenseKZT != (expByMonth[m.monthKey] ?? 0) { return false }
            if m.incomeKZT != (incByMonth[m.monthKey] ?? 0) { return false }
        }
        return true
    }
}
