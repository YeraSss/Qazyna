import SwiftUI
import SwiftData

/// Monthly category budgets with progress bars and colored warnings (80% / 100% by default).
struct BudgetsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\CategoryBudget.categoryID)]) private var budgets: [CategoryBudget]
    @Query private var categories: [Category]
    @Query private var categoryRollups: [CategoryMonthlyRollup]
    @State private var editing: CategoryBudget?
    @State private var adding = false

    private let monthKey = DateKeys.currentMonthKey()
    private var categoryMap: [String: Category] { Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    var body: some View {
        List {
            if budgets.isEmpty {
                ContentUnavailableView("No budgets yet", systemImage: "chart.bar.doc.horizontal",
                                       description: Text("Set a monthly limit per category to track your spending pace."))
            }
            ForEach(budgets) { budget in
                BudgetRow(budget: budget, category: categoryMap[budget.categoryID], spent: spent(budget.categoryID))
                    .contentShape(Rectangle())
                    .onTapGesture { editing = budget }
                    .swipeActions {
                        Button(role: .destructive) { context.delete(budget); try? context.save() } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .navigationTitle("Budgets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { BudgetEditorView(budget: nil) }
        .sheet(item: $editing) { BudgetEditorView(budget: $0) }
    }

    private func spent(_ categoryID: String) -> Decimal {
        categoryRollups.first { $0.monthKey == monthKey && $0.categoryID == categoryID }?.expenseKZT ?? 0
    }
}

struct BudgetRow: View {
    let budget: CategoryBudget
    let category: Category?
    let spent: Decimal

    private var ratio: Double { budget.limitKZT > 0 ? min(1.2, spent.doubleValue / budget.limitKZT.doubleValue) : 0 }
    private var color: Color {
        if ratio >= 1 { return .red }
        if ratio >= (budget.thresholds.first ?? 0.8) { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(category?.emoji ?? "🏷️") \(category?.name ?? budget.categoryID)").font(.subheadline.weight(.medium))
                Spacer()
                Text("\(CurrencyFormatter.kzt(spent)) / \(CurrencyFormatter.kzt(budget.limitKZT))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 8)
                    Capsule().fill(color.gradient).frame(width: geo.size.width * min(1, ratio), height: 8)
                }
            }
            .frame(height: 8)
            if ratio >= 1 {
                Label("Over budget", systemImage: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.red)
            } else if ratio >= (budget.thresholds.first ?? 0.8) {
                Label("Approaching limit (\(Int((ratio * 100).rounded()))%)", systemImage: "exclamationmark.circle").font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
