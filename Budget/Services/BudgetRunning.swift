import Foundation

/// Computes the *running* remaining budget for expenses: for each expense transaction in a
/// category that has a monthly budget, how much of that month's limit is left after (and
/// including) it — chronologically. Negative means the budget was exceeded at that point.
enum BudgetRunning {
    static func remainingByTx(_ txs: [TransactionRecord], budgets: [String: Decimal]) -> [UUID: Decimal] {
        guard !budgets.isEmpty else { return [:] }
        let relevant = txs.filter { $0.kind == .expense && budgets[$0.categoryID] != nil }
        let grouped = Dictionary(grouping: relevant) { "\($0.monthKey)|\($0.categoryID)" }
        var result: [UUID: Decimal] = [:]
        for (_, group) in grouped {
            guard let limit = budgets[group[0].categoryID] else { continue }
            let sorted = group.sorted { a, b in
                a.date != b.date ? a.date < b.date : a.createdAt < b.createdAt
            }
            var cumulative: Decimal = 0
            for tx in sorted {
                cumulative += tx.amountKZT
                result[tx.id] = limit - cumulative
            }
        }
        return result
    }
}
