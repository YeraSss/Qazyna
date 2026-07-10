import Foundation
import SwiftData
import WidgetKit

/// A tiny snapshot the app publishes to the App Group so the widget extension can render
/// without opening the whole SwiftData store. The app writes it after data changes; the
/// widget reads it on its timeline. (The widget target ships its own copy of this struct.)
struct WidgetSnapshot: Codable {
    var netWorthKZT: Double
    var monthSpentKZT: Double
    var monthIncomeKZT: Double
    var topBudgetName: String?
    var topBudgetRatio: Double
    var updatedAt: Date

    static let filename = "widget_snapshot.json"

    static var fileURL: URL {
        ModelContainerFactory.containerDirectory().appendingPathComponent(filename)
    }
}

@MainActor
enum WidgetSnapshotWriter {
    /// Recompute and publish the widget snapshot, then nudge the widget timelines.
    static func update(in context: ModelContext, rateToKZT: (String) -> Decimal) {
        let accounts = (try? context.fetch(FetchDescriptor<SubAccount>())) ?? []
        let netWorth = NetWorthCalculator.total(accounts, rateToKZT: rateToKZT)
        let (expense, income) = AnalyticsData.monthTotals(monthKey: DateKeys.currentMonthKey(), in: context)

        let progress = BudgetAlerts.currentProgress(in: context).sorted { $0.ratio > $1.ratio }.first
        var topName: String?
        if let p = progress {
            let cats = (try? context.fetch(FetchDescriptor<Category>())) ?? []
            topName = cats.first { $0.id == p.categoryID }?.name
        }

        let snapshot = WidgetSnapshot(
            netWorthKZT: netWorth.doubleValue,
            monthSpentKZT: expense.doubleValue,
            monthIncomeKZT: income.doubleValue,
            topBudgetName: topName,
            topBudgetRatio: progress?.ratio ?? 0,
            updatedAt: Date()
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: WidgetSnapshot.fileURL, options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
