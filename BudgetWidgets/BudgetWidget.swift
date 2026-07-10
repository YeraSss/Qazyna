import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline

struct BudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct BudgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: Date(), snapshot: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        completion(BudgetEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        let entry = BudgetEntry(date: Date(), snapshot: WidgetSnapshot.load())
        // Refresh roughly hourly; the app also nudges reloads on data changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

struct BudgetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BudgetEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: lockScreenRectangular
        case .accessoryInline: Text("Spent \(entry.snapshot.kzt(entry.snapshot.monthSpentKZT))")
        case .systemMedium: mediumView
        default: smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("This month", systemImage: "creditcard").font(.caption2).foregroundStyle(.secondary)
            Text(entry.snapshot.kzt(entry.snapshot.monthSpentKZT)).font(.title3.bold()).minimumScaleFactor(0.6).lineLimit(1)
            Spacer()
            budgetBar
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Net worth").font(.caption2).foregroundStyle(.secondary)
                Text(entry.snapshot.kzt(entry.snapshot.netWorthKZT)).font(.headline).minimumScaleFactor(0.6).lineLimit(1)
                Spacer()
                Text("Spent this month").font(.caption2).foregroundStyle(.secondary)
                Text(entry.snapshot.kzt(entry.snapshot.monthSpentKZT)).font(.subheadline.weight(.semibold))
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Top budget").font(.caption2).foregroundStyle(.secondary)
                Text(entry.snapshot.topBudgetName ?? "No budgets").font(.subheadline.weight(.medium)).lineLimit(1)
                budgetBar
                Link(destination: URL(string: "budget://quickadd")!) {
                    Label("Add", systemImage: "plus.circle.fill").font(.caption)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var lockScreenRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Spent \(entry.snapshot.kzt(entry.snapshot.monthSpentKZT))").font(.headline)
            if let name = entry.snapshot.topBudgetName {
                Text("\(name) \(Int(entry.snapshot.topBudgetRatio * 100))%").font(.caption2)
            }
        }
    }

    @ViewBuilder private var budgetBar: some View {
        if entry.snapshot.topBudgetName != nil {
            let ratio = min(1, entry.snapshot.topBudgetRatio)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 6)
                    Capsule().fill(ratio >= 1 ? Color.red : ratio >= 0.8 ? .orange : .green)
                        .frame(width: geo.size.width * ratio, height: 6)
                }
            }.frame(height: 6)
        }
    }
}

// MARK: - Widget & Bundle

struct BudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BudgetWidget", provider: BudgetProvider()) { entry in
            BudgetWidgetView(entry: entry)
        }
        .configurationDisplayName("Qazyna")
        .description("Your net worth, month spending, and top budget at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct BudgetWidgetBundle: WidgetBundle {
    var body: some Widget { BudgetWidget() }
}
