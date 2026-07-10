import Foundation

/// Integer date bucket keys denormalized onto rows so every `#Predicate` filters
/// flat indexed scalars (e.g. `monthKey >= 202601 && monthKey <= 202612`) instead of
/// chaining through relationships/optionals — which SwiftData predicates handle badly.
enum DateKeys {
    /// yyyymmdd, e.g. 20260710
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// yyyymm, e.g. 202607
    static func monthKey(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month], from: date)
        return (c.year ?? 0) * 100 + (c.month ?? 0)
    }

    static func monthKey(year: Int, month: Int) -> Int { year * 100 + month }

    static func year(fromMonthKey key: Int) -> Int { key / 100 }
    static func month(fromMonthKey key: Int) -> Int { key % 100 }

    /// First moment of the month for a given yyyymm key.
    static func startOfMonth(monthKey key: Int, calendar: Calendar = .current) -> Date {
        var c = DateComponents()
        c.year = year(fromMonthKey: key)
        c.month = month(fromMonthKey: key)
        c.day = 1
        return calendar.date(from: c) ?? Date()
    }

    static func currentMonthKey(_ calendar: Calendar = .current) -> Int { monthKey(Date(), calendar: calendar) }

    /// The month key `delta` months before/after the given key (delta may be negative).
    static func monthKey(_ key: Int, offsetBy delta: Int, calendar: Calendar = .current) -> Int {
        let start = startOfMonth(monthKey: key, calendar: calendar)
        let shifted = calendar.date(byAdding: .month, value: delta, to: start) ?? start
        return monthKey(shifted, calendar: calendar)
    }

    /// Number of days in the month for a yyyymm key.
    static func daysInMonth(monthKey key: Int, calendar: Calendar = .current) -> Int {
        let start = startOfMonth(monthKey: key, calendar: calendar)
        return calendar.range(of: .day, in: .month, for: start)?.count ?? 30
    }
}
