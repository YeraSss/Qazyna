import Foundation
import SwiftData

// MARK: - Precomputed aggregation cache
//
// SwiftData has no SUM/AVG/GROUP BY. Rather than fetch-and-reduce the whole transaction
// table for every chart, we maintain flat, keyed rollup rows on every write/edit/delete
// (via `Ledger`). Charts read these directly. Rollups are a *derived cache* — never the
// source of truth — and are fully rebuildable with `Ledger.rebuildRollups(...)`.
//
// Kind is split into `expenseKZT` / `incomeKZT` columns so no rollup query ever filters
// on an enum (a known SwiftData `#Predicate` weak spot).

/// Spending/income totals for one calendar day (yyyymmdd).
@Model
final class DailyRollup {
    @Attribute(.unique) var dayKey: Int
    var monthKey: Int
    var expenseKZT: Decimal
    var incomeKZT: Decimal

    init(dayKey: Int, monthKey: Int, expenseKZT: Decimal = 0, incomeKZT: Decimal = 0) {
        self.dayKey = dayKey
        self.monthKey = monthKey
        self.expenseKZT = expenseKZT
        self.incomeKZT = incomeKZT
    }
}

/// Spending/income totals for one month (yyyymm).
@Model
final class MonthlyRollup {
    @Attribute(.unique) var monthKey: Int
    var expenseKZT: Decimal
    var incomeKZT: Decimal

    init(monthKey: Int, expenseKZT: Decimal = 0, incomeKZT: Decimal = 0) {
        self.monthKey = monthKey
        self.expenseKZT = expenseKZT
        self.incomeKZT = incomeKZT
    }
}

/// Per-category totals within one month. Keyed by a composite "monthKey-categoryID".
@Model
final class CategoryMonthlyRollup {
    #Index<CategoryMonthlyRollup>([\.monthKey], [\.categoryID])
    @Attribute(.unique) var key: String
    var monthKey: Int
    var categoryID: String
    var expenseKZT: Decimal
    var incomeKZT: Decimal

    init(monthKey: Int, categoryID: String, expenseKZT: Decimal = 0, incomeKZT: Decimal = 0) {
        self.key = Self.key(monthKey: monthKey, categoryID: categoryID)
        self.monthKey = monthKey
        self.categoryID = categoryID
        self.expenseKZT = expenseKZT
        self.incomeKZT = incomeKZT
    }

    static func key(monthKey: Int, categoryID: String) -> String { "\(monthKey)-\(categoryID)" }
}

/// A point in the net-worth time series (yyyymmdd → KZT), computed at the latest rate.
@Model
final class NetWorthSnapshot {
    @Attribute(.unique) var dayKey: Int
    var netWorthKZT: Decimal
    var date: Date

    init(dayKey: Int, netWorthKZT: Decimal, date: Date) {
        self.dayKey = dayKey
        self.netWorthKZT = netWorthKZT
        self.date = date
    }
}
