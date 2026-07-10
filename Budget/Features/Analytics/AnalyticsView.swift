import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct AnalyticsView: View {
    @Environment(\.modelContext) private var context
    @State private var pdfDoc: DataDocument?
    @State private var exportingPDF = false
    // Re-render when transactions or rollups change.
    @Query private var monthlyRollups: [MonthlyRollup]
    @Query private var dailyRollups: [DailyRollup]
    @Query private var categoryRollups: [CategoryMonthlyRollup]

    @State private var monthKey = DateKeys.currentMonthKey()
    @State private var chartMode: ChartMode = .category

    enum ChartMode: String, CaseIterable, Identifiable { case category = "Category", daily = "Daily", trend = "Trend"; var id: String { rawValue } }

    private var slices: [AnalyticsData.CategorySlice] { AnalyticsData.categorySlices(monthKey: monthKey, in: context) }
    private var totals: (expense: Decimal, income: Decimal) { AnalyticsData.monthTotals(monthKey: monthKey, in: context) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthSelector
                    summaryCard
                    chartModePicker
                    chartCard
                    insightsSection
                    managementLinks
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Analytics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { exportPDF() } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
            .fileExporter(isPresented: $exportingPDF, document: pdfDoc, contentType: .pdf,
                          defaultFilename: "budget-report-\(monthKey)") { _ in }
        }
    }

    private func exportPDF() {
        if let data = ReportBuilder.makePDF(monthKey: monthKey, in: context) {
            pdfDoc = DataDocument(data: data)
            exportingPDF = true
            Haptics.tap()
        }
    }

    private var monthSelector: some View {
        HStack {
            Button { monthKey = DateKeys.monthKey(monthKey, offsetBy: -1); Haptics.selection() } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(DateKeys.startOfMonth(monthKey: monthKey).formatted(.dateTime.month(.wide).year())).font(.headline)
            Spacer()
            Button { monthKey = DateKeys.monthKey(monthKey, offsetBy: 1); Haptics.selection() } label: { Image(systemName: "chevron.right") }
                .disabled(monthKey >= DateKeys.currentMonthKey())
        }
        .padding(.horizontal, 4)
    }

    private var summaryCard: some View {
        HStack {
            stat("Spent", totals.expense, .primary)
            Divider().frame(height: 34)
            stat("Income", totals.income, .green)
            Divider().frame(height: 34)
            stat("Net", totals.income - totals.expense, totals.income - totals.expense >= 0 ? .green : .red)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func stat(_ title: String, _ value: Decimal, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(CurrencyFormatter.kzt(value)).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity)
    }

    private var chartModePicker: some View {
        Picker("Chart", selection: $chartMode) {
            ForEach(ChartMode.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented)
    }

    @ViewBuilder private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch chartMode {
            case .category: categoryChart
            case .daily: dailyChart
            case .trend: trendChart
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: Category donut + legend (legend rows drill into filtered history)

    @ViewBuilder private var categoryChart: some View {
        if slices.isEmpty {
            emptyChart("No spending this month")
        } else {
            Chart(slices) { slice in
                SectorMark(angle: .value("Amount", slice.amountKZT.doubleValue),
                           innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(Color(hex: slice.colorHex))
            }
            .frame(height: 220)
            .overlay {
                VStack(spacing: 2) {
                    Text("Total").font(.caption2).foregroundStyle(.secondary)
                    Text(CurrencyFormatter.compactKZT(totals.expense)).font(.headline)
                }
            }
            VStack(spacing: 0) {
                ForEach(slices) { slice in
                    NavigationLink {
                        CategoryTransactionsView(monthKey: monthKey, categoryID: slice.categoryID, title: slice.name)
                    } label: { legendRow(slice) }
                        .buttonStyle(.plain)
                    if slice.id != slices.last?.id { Divider() }
                }
            }
        }
    }

    private func legendRow(_ slice: AnalyticsData.CategorySlice) -> some View {
        let pct = totals.expense > 0 ? Int((slice.amountKZT.doubleValue / totals.expense.doubleValue * 100).rounded()) : 0
        return HStack(spacing: 10) {
            Circle().fill(Color(hex: slice.colorHex)).frame(width: 10, height: 10)
            Text("\(slice.emoji) \(slice.name)").font(.subheadline)
            Spacer()
            Text("\(pct)%").font(.caption).foregroundStyle(.secondary)
            Text(CurrencyFormatter.kzt(slice.amountKZT)).font(.subheadline.weight(.medium))
            Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: Daily bars

    @ViewBuilder private var dailyChart: some View {
        let daily = AnalyticsData.dailySeries(monthKey: monthKey, in: context)
        let avg = totals.expense > 0 ? totals.expense.doubleValue / Double(max(1, daily.filter { $0.expenseKZT > 0 }.count)) : 0
        if daily.allSatisfy({ $0.expenseKZT == 0 }) {
            emptyChart("No spending this month")
        } else {
            Text("Daily spending").font(.subheadline.weight(.medium))
            Chart {
                ForEach(daily) { d in
                    BarMark(x: .value("Day", d.date, unit: .day),
                            y: .value("Spent", d.expenseKZT.doubleValue))
                        .foregroundStyle(Color.accentColor.gradient)
                }
                if avg > 0 {
                    RuleMark(y: .value("Average", avg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("avg \(CurrencyFormatter.compactKZT(Decimal(safe: avg)))").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .frame(height: 220)
            .chartYAxis { AxisMarks(format: CompactKZTFormat()) }
        }
    }

    // MARK: 6-month trend

    @ViewBuilder private var trendChart: some View {
        let months = AnalyticsData.monthlySeries(endingAt: monthKey, count: 6, in: context)
        Text("Last 6 months").font(.subheadline.weight(.medium))
        Chart {
            ForEach(months) { m in
                BarMark(x: .value("Month", m.label), y: .value("Spent", m.expenseKZT.doubleValue))
                    .foregroundStyle(by: .value("Type", "Spent"))
                    .position(by: .value("Type", "Spent"))
                BarMark(x: .value("Month", m.label), y: .value("Income", m.incomeKZT.doubleValue))
                    .foregroundStyle(by: .value("Type", "Income"))
                    .position(by: .value("Type", "Income"))
            }
        }
        .chartForegroundStyleScale(["Spent": Color.red.opacity(0.8), "Income": Color.green.opacity(0.8)])
        .frame(height: 220)
        .chartYAxis { AxisMarks(format: CompactKZTFormat()) }
    }

    private func emptyChart(_ msg: String) -> some View {
        Text(msg).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 180)
    }

    // MARK: Insights + navigation

    private var insightsSection: some View {
        let insights = InsightsEngine.insights(monthKey: monthKey, in: context)
        return Group {
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Insights").font(.headline).padding(.horizontal, 4)
                    ForEach(insights) { InsightCard(insight: $0) }
                }
            }
        }
    }

    private var managementLinks: some View {
        VStack(spacing: 0) {
            navRow("Budgets", "chart.bar.doc.horizontal") { BudgetsView() }
            Divider().padding(.leading, 48)
            navRow("Savings Goals", "target") { GoalsView() }
            Divider().padding(.leading, 48)
            navRow("Recurring", "repeat") { RecurringView() }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func navRow<Destination: View>(_ title: String, _ icon: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(.tint).frame(width: 24)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct InsightCard: View {
    let insight: InsightsEngine.Insight
    private var color: Color {
        switch insight.tint {
        case .neutral: return .accentColor
        case .good: return .green
        case .warning: return .orange
        case .bad: return .red
        }
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: insight.systemImage).foregroundStyle(color).font(.title3).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title).font(.subheadline.weight(.semibold))
                Text(insight.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// Compact KZT axis label format for Swift Charts.
struct CompactKZTFormat: FormatStyle {
    func format(_ value: Double) -> String { CurrencyFormatter.compactKZT(Decimal(safe: value)) }
}
