import XCTest
import SwiftData
@testable import Budget

/// Unit tests for the critical financial logic. Mirrors the in-app `LedgerSelfTest` but as a
/// conventional XCTest suite (`xcodebuild test` / ⌘U). Uses an in-memory store.
final class BudgetTests: XCTestCase {

    @MainActor
    private func makeContext() -> (ModelContext, SubAccount, SubAccount) {
        let container = ModelContainerFactory.makeContainer(inMemory: true)
        let ctx = ModelContext(container)
        SeedData.seedIfNeeded(ctx)
        let bank = Bank(id: "t.bank", name: "Test", domain: "", brandColorHex: "#33F")
        ctx.insert(bank)
        let card = SubAccount(name: "Card", type: .card, currencyCode: "KZT", openingBalance: 100_000)
        let usd = SubAccount(name: "USD", type: .savings, currencyCode: "USD", openingBalance: 1_000)
        card.bank = bank; usd.bank = bank
        ctx.insert(card); ctx.insert(usd)
        try? ctx.save()
        return (ctx, card, usd)
    }

    @MainActor
    private func monthExpense(_ ctx: ModelContext) -> Decimal {
        let mk = DateKeys.currentMonthKey()
        var d = FetchDescriptor<MonthlyRollup>(predicate: #Predicate { $0.monthKey == mk }); d.fetchLimit = 1
        return (try? ctx.fetch(d).first?.expenseKZT) ?? 0
    }

    @MainActor
    func testInsertUpdatesBalanceAndRollup() throws {
        let (ctx, card, _) = makeContext()
        try Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 25_000, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: card.id, categoryID: "food"), in: ctx)
        XCTAssertEqual(card.cachedBalance, 75_000)
        XCTAssertEqual(monthExpense(ctx), 25_000)
    }

    @MainActor
    func testEditReversesAndReposts() throws {
        let (ctx, card, _) = makeContext()
        let tx = try Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 25_000, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: card.id, categoryID: "food"), in: ctx)
        try Ledger.update(tx, with: TransactionDraft(id: tx.id, kind: .expense, amountOriginal: 30_000,
            currencyCode: "KZT", fxRateToKZT: 1, accountID: card.id, categoryID: "transport"), in: ctx)
        XCTAssertEqual(card.cachedBalance, 70_000)
        XCTAssertEqual(monthExpense(ctx), 30_000)
        XCTAssertTrue(Ledger.integrityCheck(in: ctx))
    }

    @MainActor
    func testDeleteAndTransferAndAdjust() throws {
        let (ctx, card, _) = makeContext()
        let tx = try Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 10_000, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: card.id, categoryID: "food"), in: ctx)
        try Ledger.delete(tx, in: ctx)
        XCTAssertEqual(card.cachedBalance, 100_000)
        XCTAssertEqual(monthExpense(ctx), 0)

        let cash = SubAccount(name: "Cash", type: .cash, currencyCode: "KZT", openingBalance: 0)
        ctx.insert(cash); try? ctx.save()
        try Ledger.transfer(TransferDraft(fromAccountID: card.id, toAccountID: cash.id,
            fromAmount: 40_000, fromCurrencyCode: "KZT", toAmount: 40_000, toCurrencyCode: "KZT"), in: ctx)
        XCTAssertEqual(card.cachedBalance, 60_000)
        XCTAssertEqual(cash.cachedBalance, 40_000)
        XCTAssertEqual(monthExpense(ctx), 0, "transfer is not spending")

        try Ledger.adjustBalance(card, to: 99_999, reason: nil, in: ctx)
        XCTAssertEqual(card.cachedBalance, 99_999)
        XCTAssertTrue(Ledger.integrityCheck(in: ctx))
    }

    @MainActor
    func testRebuildPreservesTotals() throws {
        let (ctx, card, _) = makeContext()
        try Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 12_345, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: card.id, categoryID: "food"), in: ctx)
        try Ledger.rebuildRollups(in: ctx)
        try Ledger.rebuildBalances(in: ctx)
        XCTAssertTrue(Ledger.integrityCheck(in: ctx))
        XCTAssertEqual(monthExpense(ctx), 12_345)
    }

    func testAmountParser() {
        XCTAssertEqual(AmountParser.parse("1 234,56", currencyCode: "USD"), Decimal(string: "1234.56"))
        XCTAssertEqual(AmountParser.parse("1,234.56", currencyCode: "USD"), Decimal(string: "1234.56"))
        XCTAssertEqual(AmountParser.parse("2 990", currencyCode: "KZT"), 2_990)
        XCTAssertEqual(AmountParser.parse("2,990", currencyCode: "KZT"), 2_990) // grouping, not decimal
        XCTAssertEqual(AmountParser.parse("₸ 15 000", currencyCode: "KZT"), 15_000)
        XCTAssertEqual(AmountParser.parse("$12.34", currencyCode: "USD"), Decimal(string: "12.34"))
    }

    @MainActor
    func testTapLoggerRoutingAndIdempotency() throws {
        let (ctx, card, _) = makeContext()
        ctx.insert(CardMapping(cardKey: CardMapping.normalize("Kaspi Gold"), displayCardName: "Kaspi Gold",
                               accountID: card.id, defaultCurrencyCode: "KZT"))
        try? ctx.save()
        let r1 = try TapLogger.log(rawAmount: "3 500", merchant: "Magnum", card: "Kaspi Gold", currency: nil, in: ctx)
        XCTAssertEqual(r1.transaction.amountOriginal, 3_500)
        XCTAssertEqual(r1.transaction.accountID, card.id)
        XCTAssertTrue(r1.needsReview)
        XCTAssertEqual(card.cachedBalance, 96_500)
        let r2 = try TapLogger.log(rawAmount: "3 500", merchant: "Magnum", card: "Kaspi Gold", currency: nil, in: ctx)
        XCTAssertEqual(r2.transaction.id, r1.transaction.id, "duplicate tap deduped")
        XCTAssertEqual(card.cachedBalance, 96_500, "no double-count")
    }

    @MainActor
    func testNLParser() {
        let (ctx, card, _) = makeContext()
        let e1 = NLParser.parseHeuristic("coffee 1500", in: ctx)
        XCTAssertEqual(e1.amount, 1_500)
        XCTAssertEqual(e1.categoryID, "food")
        XCTAssertEqual(e1.kind, .expense)
        let e2 = NLParser.parseHeuristic("salary 600000 card", in: ctx)
        XCTAssertEqual(e2.kind, .income)
        XCTAssertEqual(e2.amount, 600_000)
        XCTAssertEqual(e2.accountID, card.id)
    }

    @MainActor
    func testCSVRoundTripAndImport() throws {
        let (ctx, card, _) = makeContext()
        try Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 5_000, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: card.id, categoryID: "food"), in: ctx)
        let csv = ImportExportService.transactionsCSV(in: ctx)
        let parsed = ImportExportService.parseCSV(csv)
        XCTAssertEqual(parsed.first?.first, "date")
        XCTAssertGreaterThanOrEqual(parsed.count, 2)

        let sample = "date,amount,merchant,type\n2026-07-05,1200,Shop,expense\n2026-07-06,3400,Other,expense"
        let rows = ImportExportService.parseCSV(sample)
        let mapping = ImportExportService.CSVMapping(date: 0, amount: 1, merchant: 2, category: nil, note: nil, kind: 3)
        let n = ImportExportService.importCSV(rows: Array(rows.dropFirst()), mapping: mapping, into: card, fxRate: 1, in: ctx)
        XCTAssertEqual(n, 2)
    }

    func testCurrencyFormattingKZT() {
        XCTAssertTrue(CurrencyFormatter.kzt(1_234_567).contains("₸"))
        XCTAssertFalse(CurrencyFormatter.kzt(1_000).contains(".")) // no fraction digits for KZT
    }

    @MainActor
    func testNetWorthWithLiabilityAndFX() {
        let (ctx, card, usd) = makeContext()
        _ = ctx
        let loan = SubAccount(name: "Loan", type: .loan, currencyCode: "KZT", openingBalance: 50_000)
        let rate: (String) -> Decimal = { $0 == "USD" ? 500 : 1 }
        // card 100,000 + usd 1,000*500=500,000 - loan 50,000 = 550,000
        let total = NetWorthCalculator.total([card, usd, loan], rateToKZT: rate)
        XCTAssertEqual(total, 550_000)
    }

    /// Proves the migration path used when changing bundle id / reinstalling:
    /// Export JSON backup → restore into a fresh, empty store → nothing lost.
    @MainActor
    func testJSONBackupRestoreRoundTrip() throws {
        let (ctx, card, _) = makeContext()
        try Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 12_345, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: card.id, categoryID: "food", merchant: "Cafe"), in: ctx)
        try Ledger.insert(TransactionDraft(kind: .income, amountOriginal: 50_000, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: card.id, categoryID: "salary"), in: ctx)
        ctx.insert(CategoryBudget(categoryID: "food", limitKZT: 40_000))
        ctx.insert(SavingsGoal(name: "Fund", targetKZT: 100_000, linkedAccountID: card.id))
        try ctx.save()
        let cardBalanceBefore = card.cachedBalance   // 100,000 − 12,345 + 50,000 = 137,655

        guard let data = ImportExportService.exportBackup(in: ctx) else {
            XCTFail("backup export returned nil"); return
        }

        // Restore into a completely separate, fresh store (simulates the new app).
        let fresh = ModelContext(ModelContainerFactory.makeContainer(inMemory: true))
        try ImportExportService.restoreBackup(data, in: fresh)

        XCTAssertEqual(try fresh.fetch(FetchDescriptor<Bank>()).count, 1)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<SubAccount>()).count, 2)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<TransactionRecord>()).count, 2)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<CategoryBudget>()).count, 1)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<SavingsGoal>()).count, 1)

        let restoredCard = try fresh.fetch(FetchDescriptor<SubAccount>()).first { $0.id == card.id }
        XCTAssertEqual(restoredCard?.cachedBalance, cardBalanceBefore, "balance preserved")
        XCTAssertNotNil(restoredCard?.bank, "bank relationship reconnected")
        XCTAssertTrue(Ledger.integrityCheck(in: fresh), "rollups + balances consistent after restore")
    }

    /// Adversarial fidelity check: varied currencies, decimal balances, two banks, and a
    /// manual balance adjustment — mirrors real usage. Every field must survive exactly.
    @MainActor
    func testBackupRestoreFidelityWithAdjustmentsAndCurrencies() throws {
        let ctx = ModelContext(ModelContainerFactory.makeContainer(inMemory: true))
        SeedData.seedIfNeeded(ctx)

        let kaspi = Bank(id: "kaspi.kz", name: "Kaspi", domain: "kaspi.kz", brandColorHex: "#F14635")
        let freedom = Bank(id: "custom-1", name: "Freedom", domain: "", brandColorHex: "#51AF3D")
        ctx.insert(kaspi); ctx.insert(freedom)

        let card = SubAccount(name: "Kaspi Gold", type: .card, currencyCode: "KZT", openingBalance: 250_000)
        let usd = SubAccount(name: "USD Savings", type: .savings, currencyCode: "USD",
                             openingBalance: Decimal(string: "500.50")!)
        card.bank = kaspi; usd.bank = freedom
        ctx.insert(card); ctx.insert(usd)
        try ctx.save()

        try Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 12_345, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: card.id, categoryID: "food"), in: ctx)
        try Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: Decimal(string: "40.25")!,
            currencyCode: "USD", fxRateToKZT: Decimal(string: "468.77")!, accountID: usd.id, categoryID: "shopping"), in: ctx)
        // Manual balance correction — creates a BalanceAdjustment ledger entry.
        try Ledger.adjustBalance(card, to: 300_000, reason: "correction", in: ctx)

        let cardBalBefore = card.cachedBalance   // adjusted to 300,000
        let usdBalBefore = usd.cachedBalance     // 500.50 − 40.25 = 460.25

        guard let data = ImportExportService.exportBackup(in: ctx) else { XCTFail("nil backup"); return }
        let fresh = ModelContext(ModelContainerFactory.makeContainer(inMemory: true))
        SeedData.seedIfNeeded(fresh)   // new app already seeded default categories
        try ImportExportService.restoreBackup(data, in: fresh)

        let banks = try fresh.fetch(FetchDescriptor<Bank>())
        XCTAssertEqual(Set(banks.map(\.name)), ["Kaspi", "Freedom"], "both banks restored")

        let accts = try fresh.fetch(FetchDescriptor<SubAccount>())
        let rCard = accts.first { $0.id == card.id }
        let rUsd = accts.first { $0.id == usd.id }
        XCTAssertEqual(rUsd?.currencyCode, "USD", "USD account currency preserved")
        XCTAssertEqual(rUsd?.cachedBalance, usdBalBefore, "USD decimal balance preserved (460.25)")
        XCTAssertEqual(rCard?.cachedBalance, cardBalBefore, "card balance preserved INCLUDING manual adjustment (300,000)")
        XCTAssertNotNil(rCard?.bank, "bank link reconnected")
        XCTAssertTrue(Ledger.integrityCheck(in: fresh))
    }

    /// Flags, mappings, and relationships that the old backup silently dropped.
    @MainActor
    func testBackupRestorePreservesFlagsMappingsAndRelationships() throws {
        let ctx = ModelContext(ModelContainerFactory.makeContainer(inMemory: true))
        SeedData.seedIfNeeded(ctx)
        let bank = Bank(id: "b1", name: "B", domain: "", brandColorHex: "#123456")
        ctx.insert(bank)
        let active = SubAccount(name: "Active", type: .card, currencyCode: "KZT", openingBalance: 100_000)
        let archived = SubAccount(name: "Closed", type: .savings, currencyCode: "KZT",
                                  openingBalance: 300_000, isArchived: true)
        active.bank = bank; archived.bank = bank
        ctx.insert(active); ctx.insert(archived)
        try ctx.save()

        _ = try Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 5_000, currencyCode: "KZT",
            fxRateToKZT: 1, accountID: active.id, categoryID: "other", merchant: "Магнум",
            source: .tapToTrack, needsReview: true), in: ctx)
        ctx.insert(RecurringRule(title: "Rent", kind: .expense, amountOriginal: 250_000, currencyCode: "KZT",
            accountID: active.id, categoryID: "rent", frequency: .monthly, nextRun: Date(), autoLog: true, isActive: false))
        MerchantLearning.learn(merchant: "Магнум", categoryID: "groceries", in: ctx)
        ctx.insert(CardMapping(cardKey: CardMapping.normalize("Kaspi Gold"), displayCardName: "Kaspi Gold",
                               accountID: active.id, defaultCurrencyCode: "KZT"))
        try ctx.save()

        guard let data = ImportExportService.exportBackup(in: ctx) else { XCTFail("nil backup"); return }
        let fresh = ModelContext(ModelContainerFactory.makeContainer(inMemory: true))
        SeedData.seedIfNeeded(fresh)
        try ImportExportService.restoreBackup(data, in: fresh)

        let accts = try fresh.fetch(FetchDescriptor<SubAccount>())
        XCTAssertEqual(accts.first { $0.id == archived.id }?.isArchived, true, "archived flag preserved")
        XCTAssertEqual(NetWorthCalculator.total(accts, rateToKZT: { _ in 1 }), 95_000,
                       "net worth excludes the archived account (100k − 5k)")
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<RecurringRule>()).first?.isActive, false,
                       "paused recurring rule stays paused (no spurious auto-post)")
        let rtx = try fresh.fetch(FetchDescriptor<TransactionRecord>())
        XCTAssertEqual(rtx.first?.needsReview, true, "needsReview flag preserved")
        XCTAssertNotNil(rtx.first?.account, "tx.account relationship reconnected")
        XCTAssertEqual(MerchantLearning.category(for: "Магнум", in: fresh), "groceries", "merchant mapping preserved")
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<CardMapping>()).count, 1, "card mapping preserved")
        XCTAssertTrue(Ledger.integrityCheck(in: fresh))
    }

    /// Running account balance ("остаток") after each transaction — the user's example:
    /// 30 000 in the account, a 5 000 expense → 25 000 left.
    @MainActor
    func testRunningBalanceOstatok() throws {
        let ctx = ModelContext(ModelContainerFactory.makeContainer(inMemory: true))
        SeedData.seedIfNeeded(ctx)
        let bank = Bank(id: "b", name: "B", domain: "", brandColorHex: "#111111"); ctx.insert(bank)
        let card = SubAccount(name: "C", type: .card, currencyCode: "KZT", openingBalance: 30_000)
        card.bank = bank; ctx.insert(card)
        try ctx.save()
        let cal = Calendar.current
        let t1 = try Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 5_000, currencyCode: "KZT",
            fxRateToKZT: 1, date: cal.date(byAdding: .day, value: -2, to: .now)!, accountID: card.id, categoryID: "food"), in: ctx)
        let t2 = try Ledger.insert(TransactionDraft(kind: .income, amountOriginal: 10_000, currencyCode: "KZT",
            fxRateToKZT: 1, date: cal.date(byAdding: .day, value: -1, to: .now)!, accountID: card.id, categoryID: "salary"), in: ctx)

        let txs = try ctx.fetch(FetchDescriptor<TransactionRecord>())
        let map = RunningBalance.byTx(accounts: [card], transactions: txs, transfers: [], adjustments: [])
        XCTAssertEqual(map[t1.id], 25_000, "30 000 − 5 000 = 25 000 after the expense")
        XCTAssertEqual(map[t2.id], 35_000, "25 000 + 10 000 income")
        XCTAssertEqual(map[t2.id], card.cachedBalance, "final остаток equals the account's current balance")
    }
}
