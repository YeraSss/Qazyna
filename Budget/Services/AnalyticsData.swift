import Foundation
import SwiftData

/// Read-only helpers that assemble chart data from the precomputed rollups (never a raw
/// transaction table scan). All values are in KZT.
enum AnalyticsData {

    struct CategorySlice: Identifiable {
        let categoryID: String
        let name: String
        let emoji: String
        let colorHex: String
        let amountKZT: Decimal
        var id: String { categoryID }
    }

    struct DayPoint: Identifiable {
        let dayKey: Int
        let date: Date
        let expenseKZT: Decimal
        var id: Int { dayKey }
    }

    struct MonthPoint: Identifiable {
        let monthKey: Int
        let label: String
        let expenseKZT: Decimal
        let incomeKZT: Decimal
        var id: Int { monthKey }
    }

    /// Expense breakdown by category for a month, largest first.
    static func categorySlices(monthKey: Int, in context: ModelContext) -> [CategorySlice] {
        let mk = monthKey
        let rollups = (try? context.fetch(FetchDescriptor<CategoryMonthlyRollup>(
            predicate: #Predicate { $0.monthKey == mk }))) ?? []
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return rollups
            .filter { $0.expenseKZT > 0 }
            .map { r in
                let c = byID[r.categoryID]
                return CategorySlice(categoryID: r.categoryID,
                                     name: c?.name ?? r.categoryID,
                                     emoji: c?.emoji ?? "📦",
                                     colorHex: c?.colorHex ?? "#90A4AE",
                                     amountKZT: r.expenseKZT)
            }
            .sorted { $0.amountKZT > $1.amountKZT }
    }

    /// Daily expense series for a month (fills missing days with 0).
    static func dailySeries(monthKey: Int, in context: ModelContext) -> [DayPoint] {
        let mk = monthKey
        let rollups = (try? context.fetch(FetchDescriptor<DailyRollup>(
            predicate: #Predicate { $0.monthKey == mk }))) ?? []
        let byDay = Dictionary(rollups.map { ($0.dayKey, $0.expenseKZT) }, uniquingKeysWith: { a, _ in a })
        let cal = Calendar.current
        let days = DateKeys.daysInMonth(monthKey: mk)
        return (1...days).map { day in
            let dk = mk * 100 + day
            var comps = DateComponents(); comps.year = mk / 100; comps.month = mk % 100; comps.day = day
            let date = cal.date(from: comps) ?? Date()
            return DayPoint(dayKey: dk, date: date, expenseKZT: byDay[dk] ?? 0)
        }
    }

    /// Trailing `count` months of expense/income totals, oldest → newest.
    static func monthlySeries(endingAt monthKey: Int, count: Int, in context: ModelContext) -> [MonthPoint] {
        let all = (try? context.fetch(FetchDescriptor<MonthlyRollup>())) ?? []
        let byMonth = Dictionary(all.map { ($0.monthKey, $0) }, uniquingKeysWith: { a, _ in a })
        return (0..<count).reversed().map { back in
            let mk = DateKeys.monthKey(monthKey, offsetBy: -back)
            let r = byMonth[mk]
            let label = DateKeys.startOfMonth(monthKey: mk).formatted(.dateTime.month(.abbreviated))
            return MonthPoint(monthKey: mk, label: label,
                              expenseKZT: r?.expenseKZT ?? 0, incomeKZT: r?.incomeKZT ?? 0)
        }
    }

    static func monthTotals(monthKey: Int, in context: ModelContext) -> (expense: Decimal, income: Decimal) {
        let mk = monthKey
        var d = FetchDescriptor<MonthlyRollup>(predicate: #Predicate { $0.monthKey == mk }); d.fetchLimit = 1
        let r = try? context.fetch(d).first
        return (r?.expenseKZT ?? 0, r?.incomeKZT ?? 0)
    }
}
