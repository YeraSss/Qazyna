import Foundation
import SwiftData

/// Derives human-readable insights from the rollups: biggest category, month-over-month
/// change, average daily spend, projected month-end total, budget-pace warnings, and spikes.
enum InsightsEngine {

    struct Insight: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let systemImage: String
        let tint: InsightTint
    }
    enum InsightTint { case neutral, good, warning, bad }

    static func insights(monthKey: Int = DateKeys.currentMonthKey(), in context: ModelContext) -> [Insight] {
        var out: [Insight] = []
        let (expense, income) = AnalyticsData.monthTotals(monthKey: monthKey, in: context)
        let slices = AnalyticsData.categorySlices(monthKey: monthKey, in: context)
        let cal = Calendar.current
        let isCurrentMonth = monthKey == DateKeys.currentMonthKey()
        let daysInMonth = DateKeys.daysInMonth(monthKey: monthKey)
        let dayOfMonth = isCurrentMonth ? cal.component(.day, from: Date()) : daysInMonth
        let elapsed = max(1, dayOfMonth)

        // Biggest category.
        if let top = slices.first, expense > 0 {
            let pct = Int((top.amountKZT.doubleValue / expense.doubleValue * 100).rounded())
            out.append(Insight(title: "Biggest category: \(top.emoji) \(top.name)",
                               detail: "\(CurrencyFormatter.kzt(top.amountKZT)) — \(pct)% of this month's spending.",
                               systemImage: "chart.pie.fill", tint: .neutral))
        }

        // Month over month.
        let prevKey = DateKeys.monthKey(monthKey, offsetBy: -1)
        let (prevExpense, _) = AnalyticsData.monthTotals(monthKey: prevKey, in: context)
        if prevExpense > 0 {
            let change = (expense.doubleValue - prevExpense.doubleValue) / prevExpense.doubleValue * 100
            let up = change >= 0
            out.append(Insight(title: up ? "Spending up \(Int(abs(change).rounded()))%" : "Spending down \(Int(abs(change).rounded()))%",
                               detail: "vs last month (\(CurrencyFormatter.kzt(prevExpense))).",
                               systemImage: up ? "arrow.up.right" : "arrow.down.right",
                               tint: up ? .warning : .good))
        }

        // Average daily + projected month-end.
        if expense > 0 {
            let avgDaily = expense / Decimal(elapsed)
            out.append(Insight(title: "Avg \(CurrencyFormatter.kzt(Money.roundedKZT(avgDaily)))/day",
                               detail: "over \(elapsed) day\(elapsed == 1 ? "" : "s") this month.",
                               systemImage: "calendar", tint: .neutral))
            if isCurrentMonth {
                let projected = Money.roundedKZT(avgDaily * Decimal(daysInMonth))
                out.append(Insight(title: "Projected month-end: \(CurrencyFormatter.kzt(projected))",
                                   detail: "at your current pace.",
                                   systemImage: "chart.line.uptrend.xyaxis", tint: .neutral))
            }
        }

        // Net position.
        if income > 0 || expense > 0 {
            let net = income - expense
            out.append(Insight(title: net >= 0 ? "Net positive: \(CurrencyFormatter.kzt(net))" : "Net negative: \(CurrencyFormatter.kzt(net))",
                               detail: "income \(CurrencyFormatter.kzt(income)) − spending \(CurrencyFormatter.kzt(expense)).",
                               systemImage: "equal.circle", tint: net >= 0 ? .good : .bad))
        }

        // Budget pace warnings.
        let progress = BudgetAlerts.currentProgress(in: context, monthKey: monthKey)
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let nameByID = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        for p in progress where p.limitKZT > 0 {
            let name = nameByID[p.categoryID] ?? p.categoryID
            if p.ratio >= 1.0 {
                out.append(Insight(title: "Over budget: \(name)",
                                   detail: "\(CurrencyFormatter.kzt(p.spentKZT)) of \(CurrencyFormatter.kzt(p.limitKZT)).",
                                   systemImage: "exclamationmark.triangle.fill", tint: .bad))
            } else if isCurrentMonth, p.spentKZT > 0 {
                // Pace: projected spend for this category vs limit → "exceed by the Nth".
                let projected = p.spentKZT.doubleValue / Double(elapsed) * Double(daysInMonth)
                if projected > p.limitKZT.doubleValue {
                    let dailyRate = p.spentKZT.doubleValue / Double(elapsed)
                    if dailyRate > 0 {
                        let dayCrossed = Int((p.limitKZT.doubleValue / dailyRate).rounded(.up))
                        if dayCrossed <= daysInMonth {
                            out.append(Insight(title: "\(name) budget pace",
                                               detail: "At this rate you'll exceed it around the \(ordinal(dayCrossed)).",
                                               systemImage: "gauge.with.dots.needle.67percent", tint: .warning))
                        }
                    }
                } else if p.ratio >= 0.8 {
                    out.append(Insight(title: "\(name) at \(Int((p.ratio * 100).rounded()))%",
                                       detail: "\(CurrencyFormatter.kzt(p.spentKZT)) of \(CurrencyFormatter.kzt(p.limitKZT)).",
                                       systemImage: "gauge.medium", tint: .warning))
                }
            }
        }

        // Unusual daily spike (a day > 2.5× the daily average).
        let daily = AnalyticsData.dailySeries(monthKey: monthKey, in: context).filter { $0.expenseKZT > 0 }
        if daily.count >= 3, expense > 0 {
            let avg = expense.doubleValue / Double(daily.count)
            if let spike = daily.max(by: { $0.expenseKZT < $1.expenseKZT }), spike.expenseKZT.doubleValue > avg * 2.5 {
                out.append(Insight(title: "Spending spike",
                                   detail: "\(CurrencyFormatter.kzt(spike.expenseKZT)) on \(spike.date.formatted(.dateTime.month().day())) — well above your daily average.",
                                   systemImage: "bolt.fill", tint: .warning))
            }
        }

        return out
    }

    private static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)th"
    }
}
