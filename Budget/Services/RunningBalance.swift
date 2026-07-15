import Foundation

/// Computes the account **balance after each transaction** (the statement-style "остаток"):
/// for every transaction, how much is left in its account right after it. Interleaves that
/// account's transactions, transfers, and manual adjustments chronologically from the
/// account's opening balance. Values are in each account's own currency.
enum RunningBalance {
    private struct Event { let date: Date; let order: Date; let delta: Decimal; let txID: UUID? }

    static func byTx(accounts: [SubAccount],
                     transactions: [TransactionRecord],
                     transfers: [TransferRecord],
                     adjustments: [BalanceAdjustment]) -> [UUID: Decimal] {
        var byAccount: [UUID: [Event]] = [:]
        for t in transactions {
            byAccount[t.accountID, default: []].append(Event(date: t.date, order: t.createdAt, delta: t.signedAmountOriginal, txID: t.id))
        }
        for tr in transfers {
            byAccount[tr.fromAccountID, default: []].append(Event(date: tr.date, order: tr.createdAt, delta: -tr.fromAmount, txID: nil))
            byAccount[tr.toAccountID, default: []].append(Event(date: tr.date, order: tr.createdAt, delta: tr.toAmount, txID: nil))
        }
        for adj in adjustments {
            byAccount[adj.accountID, default: []].append(Event(date: adj.date, order: adj.createdAt, delta: adj.delta, txID: nil))
        }

        let openingByID = Dictionary(accounts.map { ($0.id, $0.openingBalance) }, uniquingKeysWith: { a, _ in a })
        var result: [UUID: Decimal] = [:]
        for (accountID, events) in byAccount {
            let sorted = events.sorted { a, b in a.date != b.date ? a.date < b.date : a.order < b.order }
            var running = openingByID[accountID] ?? 0
            for e in sorted {
                running += e.delta
                if let id = e.txID { result[id] = running }
            }
        }
        return result
    }
}
