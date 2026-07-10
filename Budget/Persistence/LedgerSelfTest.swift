#if DEBUG
import Foundation
import SwiftData
import os

/// A fast, in-memory correctness harness for the `Ledger` invariants. Runs at launch in
/// DEBUG and logs PASS/FAIL, so we can confirm balances + rollups stay consistent under
/// insert / edit / delete / transfer / adjust without needing the XCTest target wired up.
/// (The proper XCTest suite lives in the testing phase.)
enum LedgerSelfTest {
    private static let log = Logger(subsystem: "com.qazyna.app", category: "selftest")
    private static var failures = 0

    static func run() {
        failures = 0
        let container = ModelContainerFactory.makeContainer(inMemory: true)
        let ctx = ModelContext(container)
        SeedData.seedIfNeeded(ctx)

        // Two accounts: KZT card + USD savings, both under one bank.
        let bank = Bank(id: "test.bank", name: "Test Bank", domain: "", brandColorHex: "#3366FF")
        ctx.insert(bank)
        let card = SubAccount(name: "Card", type: .card, currencyCode: "KZT", openingBalance: 100_000)
        let usd = SubAccount(name: "USD Savings", type: .savings, currencyCode: "USD", openingBalance: 1_000)
        card.bank = bank; usd.bank = bank
        ctx.insert(card); ctx.insert(usd)
        try? ctx.save()

        let mk = DateKeys.currentMonthKey()

        // 1. Insert an expense on the KZT card: 25,000 ₸.
        let e1 = try! Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 25_000,
            currencyCode: "KZT", fxRateToKZT: 1, accountID: card.id, categoryID: "food"), in: ctx)
        expect(card.cachedBalance == 75_000, "card balance after expense == 75,000 (got \(card.cachedBalance))")
        expect(monthExpense(mk, ctx) == 25_000, "month expense == 25,000")

        // 2. Insert income on the card: 50,000 ₸.
        _ = try! Ledger.insert(TransactionDraft(kind: .income, amountOriginal: 50_000,
            currencyCode: "KZT", fxRateToKZT: 1, accountID: card.id, categoryID: "salary"), in: ctx)
        expect(card.cachedBalance == 125_000, "card balance after income == 125,000 (got \(card.cachedBalance))")
        expect(monthIncome(mk, ctx) == 50_000, "month income == 50,000")

        // 3. Insert a USD expense: $40 at rate 500 → 20,000 ₸ in rollups; balance in USD.
        _ = try! Ledger.insert(TransactionDraft(kind: .expense, amountOriginal: 40,
            currencyCode: "USD", fxRateToKZT: 500, accountID: usd.id, categoryID: "shopping"), in: ctx)
        expect(usd.cachedBalance == 960, "usd balance == 960 (got \(usd.cachedBalance))")
        expect(monthExpense(mk, ctx) == 45_000, "month expense == 45,000 (25k + 20k)")

        // 4. Edit e1: amount 25,000 → 30,000, category food → transport.
        try! Ledger.update(e1, with: TransactionDraft(id: e1.id, kind: .expense, amountOriginal: 30_000,
            currencyCode: "KZT", fxRateToKZT: 1, accountID: card.id, categoryID: "transport"), in: ctx)
        expect(card.cachedBalance == 120_000, "card balance after edit == 120,000 (got \(card.cachedBalance))")
        expect(monthExpense(mk, ctx) == 50_000, "month expense after edit == 50,000 (30k + 20k)")
        expect(catExpense(mk, "food", ctx) == 0, "food category == 0 after recategorize")
        expect(catExpense(mk, "transport", ctx) == 30_000, "transport category == 30,000")

        // 5. Delete e1.
        try! Ledger.delete(e1, in: ctx)
        expect(card.cachedBalance == 150_000, "card balance after delete == 150,000 (got \(card.cachedBalance))")
        expect(monthExpense(mk, ctx) == 20_000, "month expense after delete == 20,000")

        // 6. Transfer 50,000 ₸ card → (treat usd as KZT-agnostic here) another KZT account.
        let cash = SubAccount(name: "Cash", type: .cash, currencyCode: "KZT", openingBalance: 0)
        cash.bank = bank; ctx.insert(cash); try? ctx.save()
        try! Ledger.transfer(TransferDraft(fromAccountID: card.id, toAccountID: cash.id,
            fromAmount: 50_000, fromCurrencyCode: "KZT", toAmount: 50_000, toCurrencyCode: "KZT"), in: ctx)
        expect(card.cachedBalance == 100_000, "card after transfer == 100,000 (got \(card.cachedBalance))")
        expect(cash.cachedBalance == 50_000, "cash after transfer == 50,000 (got \(cash.cachedBalance))")
        expect(monthExpense(mk, ctx) == 20_000, "transfer does NOT change spending (still 20,000)")

        // 7. Manual balance adjustment: set card to 111,111.
        try! Ledger.adjustBalance(card, to: 111_111, reason: "test", in: ctx)
        expect(card.cachedBalance == 111_111, "card after adjust == 111,111 (got \(card.cachedBalance))")

        // 8. Full integrity check + rebuild round-trip.
        expect(Ledger.integrityCheck(in: ctx), "integrityCheck after ops")
        try! Ledger.rebuildRollups(in: ctx)
        try! Ledger.rebuildBalances(in: ctx)
        expect(Ledger.integrityCheck(in: ctx), "integrityCheck after rebuild")
        expect(card.cachedBalance == 111_111, "card balance preserved after rebuild (adjustments count)")

        // 9. AmountParser — locale/currency-aware parsing of Shortcuts text amounts.
        expect(AmountParser.parse("1 234,56", currencyCode: "USD") == Decimal(string: "1234.56"), "parse '1 234,56' USD == 1234.56")
        expect(AmountParser.parse("1,234.56", currencyCode: "USD") == Decimal(string: "1234.56"), "parse '1,234.56' USD == 1234.56")
        expect(AmountParser.parse("2 990", currencyCode: "KZT") == 2990, "parse '2 990' KZT == 2990")
        expect(AmountParser.parse("2,990", currencyCode: "KZT") == 2990, "parse '2,990' KZT == 2990 (grouping, not decimal)")
        expect(AmountParser.parse("₸ 15 000", currencyCode: "KZT") == 15_000, "parse '₸ 15 000' KZT == 15000")
        expect(AmountParser.parse("$12.34", currencyCode: "USD") == Decimal(string: "12.34"), "parse '$12.34' USD == 12.34")

        // 10. Tap to Track — map a card, simulate a tap, verify routing + idempotency.
        let mapping = CardMapping(cardKey: CardMapping.normalize("Kaspi Gold"),
                                  displayCardName: "Kaspi Gold", accountID: card.id, defaultCurrencyCode: "KZT")
        ctx.insert(mapping); try? ctx.save()
        let beforeTap = card.cachedBalance
        let tap = try! TapLogger.log(rawAmount: "3 500", merchant: "Magnum", card: "Kaspi Gold", currency: nil, in: ctx)
        expect(tap.transaction.amountOriginal == 3_500, "tap amount parsed == 3,500 (got \(tap.transaction.amountOriginal))")
        expect(tap.transaction.accountID == card.id, "tap routed to mapped account")
        expect(tap.needsReview, "tap flagged needsReview (no learned merchant)")
        expect(card.cachedBalance == beforeTap - 3_500, "tap decremented card balance")
        let tap2 = try! TapLogger.log(rawAmount: "3 500", merchant: "Magnum", card: "Kaspi Gold", currency: nil, in: ctx)
        expect(tap2.transaction.id == tap.transaction.id, "duplicate tap deduped (same row)")
        expect(card.cachedBalance == beforeTap - 3_500, "duplicate tap did NOT double-count")

        // 11. Merchant learning: correcting the category teaches future taps.
        MerchantLearning.learn(merchant: "Magnum", categoryID: "groceries", in: ctx)
        expect(MerchantLearning.category(for: "MAGNUM", in: ctx) == "groceries", "merchant learned (case-insensitive)")

        // 12. Natural-language heuristic parser.
        let nl1 = NLParser.parseHeuristic("coffee 1500", in: ctx)
        expect(nl1.amount == 1_500, "NL parse amount == 1500 (got \(String(describing: nl1.amount)))")
        expect(nl1.categoryID == "food", "NL 'coffee' → food")
        expect(nl1.kind == .expense, "NL kind expense")
        let nl2 = NLParser.parseHeuristic("salary 600000 card", in: ctx)
        expect(nl2.kind == .income, "NL 'salary' → income")
        expect(nl2.amount == 600_000, "NL income amount == 600000")
        expect(nl2.accountID == card.id, "NL matched 'card' account")

        // 13. CSV export → parse round-trip.
        let csv = ImportExportService.transactionsCSV(in: ctx)
        let parsedCSV = ImportExportService.parseCSV(csv)
        expect(parsedCSV.first?.first == "date", "CSV header starts with 'date'")
        expect(parsedCSV.count >= 2, "CSV has header + at least one row")

        // 14. CSV import appends transactions via the Ledger.
        let sample = "date,amount,merchant,type\n2026-07-05,1200,Test Shop,expense\n2026-07-06,3400,Other,expense"
        let sampleRows = ImportExportService.parseCSV(sample)
        let csvMapping = ImportExportService.CSVMapping(date: 0, amount: 1, merchant: 2, category: nil, note: nil, kind: 3)
        let imported = ImportExportService.importCSV(rows: Array(sampleRows.dropFirst()), mapping: csvMapping,
                                                     into: card, fxRate: 1, in: ctx)
        expect(imported == 2, "CSV imported 2 rows (got \(imported))")

        if failures == 0 {
            log.notice("✅ LedgerSelfTest: ALL PASSED")
        } else {
            log.error("❌ LedgerSelfTest: \(failures) FAILURE(S)")
        }
    }

    // MARK: helpers

    private static func expect(_ condition: Bool, _ message: String) {
        if condition { log.notice("  ✓ \(message, privacy: .public)") }
        else { failures += 1; log.error("  ✗ FAIL: \(message, privacy: .public)") }
    }

    private static func monthExpense(_ mk: Int, _ ctx: ModelContext) -> Decimal {
        var d = FetchDescriptor<MonthlyRollup>(predicate: #Predicate { $0.monthKey == mk }); d.fetchLimit = 1
        return (try? ctx.fetch(d).first?.expenseKZT) ?? 0
    }
    private static func monthIncome(_ mk: Int, _ ctx: ModelContext) -> Decimal {
        var d = FetchDescriptor<MonthlyRollup>(predicate: #Predicate { $0.monthKey == mk }); d.fetchLimit = 1
        return (try? ctx.fetch(d).first?.incomeKZT) ?? 0
    }
    private static func catExpense(_ mk: Int, _ cat: String, _ ctx: ModelContext) -> Decimal {
        let key = CategoryMonthlyRollup.key(monthKey: mk, categoryID: cat)
        var d = FetchDescriptor<CategoryMonthlyRollup>(predicate: #Predicate { $0.key == key }); d.fetchLimit = 1
        return (try? ctx.fetch(d).first?.expenseKZT) ?? 0
    }
}
#endif
