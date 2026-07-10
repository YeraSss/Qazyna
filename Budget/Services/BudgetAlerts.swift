import Foundation
import SwiftData

/// Evaluates current-month category spending against `CategoryBudget` limits and fires a local
/// notification the first time each threshold (e.g. 80%, 100%) is crossed. It is event-driven
/// and self-capped: one alert per (category, month, threshold), re-armed if spend drops back
/// under the threshold (after an edit/delete). Called after every write that changes spending.
enum BudgetAlerts {
    private static let notifiedKey = "budgetNotifiedThresholds"

    /// Progress info for the UI (Phase 4 progress bars) and alerting.
    struct Progress {
        let categoryID: String
        let spentKZT: Decimal
        let limitKZT: Decimal
        var ratio: Double { limitKZT > 0 ? (spentKZT.doubleValue / limitKZT.doubleValue) : 0 }
    }

    static func currentProgress(in context: ModelContext, monthKey: Int = DateKeys.currentMonthKey()) -> [Progress] {
        let budgets = (try? context.fetch(FetchDescriptor<CategoryBudget>())) ?? []
        return budgets.map { b in
            Progress(categoryID: b.categoryID, spentKZT: spent(b.categoryID, monthKey, context), limitKZT: b.limitKZT)
        }
    }

    static func evaluate(in context: ModelContext, monthKey: Int = DateKeys.currentMonthKey()) {
        let budgets = (try? context.fetch(FetchDescriptor<CategoryBudget>())) ?? []
        guard !budgets.isEmpty else { return }
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let nameByID = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        var notified = Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? [])
        for budget in budgets {
            let spentKZT = spent(budget.categoryID, monthKey, context)
            let ratio = budget.limitKZT > 0 ? spentKZT.doubleValue / budget.limitKZT.doubleValue : 0
            for (i, threshold) in budget.thresholds.enumerated() {
                let id = "budget-\(budget.categoryID)-\(monthKey)-\(i)"
                if ratio >= threshold {
                    if !notified.contains(id) {
                        notified.insert(id)
                        let name = nameByID[budget.categoryID] ?? budget.categoryID
                        let pct = Int((threshold * 100).rounded())
                        let title = threshold >= 1.0 ? "Over budget: \(name)" : "\(pct)% of \(name) budget"
                        let body = "You've spent \(CurrencyFormatter.kzt(spentKZT)) of \(CurrencyFormatter.kzt(budget.limitKZT))."
                        NotificationService.fire(identifier: id, title: title, body: body)
                    }
                } else {
                    notified.remove(id) // re-arm when back under the threshold
                }
            }
        }
        UserDefaults.standard.set(Array(notified), forKey: notifiedKey)
    }

    private static func spent(_ categoryID: String, _ monthKey: Int, _ context: ModelContext) -> Decimal {
        let key = CategoryMonthlyRollup.key(monthKey: monthKey, categoryID: categoryID)
        var d = FetchDescriptor<CategoryMonthlyRollup>(predicate: #Predicate { $0.key == key }); d.fetchLimit = 1
        return (try? context.fetch(d).first?.expenseKZT) ?? 0
    }
}
