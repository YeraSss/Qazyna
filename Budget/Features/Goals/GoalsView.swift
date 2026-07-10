import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateService
    @Query(sort: [SortDescriptor(\SavingsGoal.createdAt)]) private var goals: [SavingsGoal]
    @Query private var accounts: [SubAccount]
    @State private var editing: SavingsGoal?
    @State private var adding = false

    var body: some View {
        List {
            if goals.isEmpty {
                ContentUnavailableView("No goals yet", systemImage: "target",
                                       description: Text("Set a savings target and track your progress."))
            }
            ForEach(goals) { goal in
                GoalRow(projection: GoalsCalculator.projection(for: goal, in: context, rateToKZT: { fx.rateToKZT($0) }),
                        name: goal.name, targetDate: goal.targetDate,
                        accountName: accountName(goal.linkedAccountID))
                    .contentShape(Rectangle())
                    .onTapGesture { editing = goal }
                    .swipeActions {
                        Button(role: .destructive) { context.delete(goal); try? context.save() } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .navigationTitle("Savings Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { GoalEditorView(goal: nil) }
        .sheet(item: $editing) { GoalEditorView(goal: $0) }
    }

    private func accountName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }.map { "\($0.bank?.name ?? "") \($0.name)" }
    }
}

struct GoalRow: View {
    let projection: GoalsCalculator.Projection
    let name: String
    let targetDate: Date?
    let accountName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                if projection.isComplete {
                    Label("Reached", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                }
            }
            HStack {
                Text(CurrencyFormatter.kzt(projection.savedKZT)).fontWeight(.semibold)
                Text("of \(CurrencyFormatter.kzt(projection.targetKZT))").foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((projection.ratio * 100).rounded()))%").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
            }
            .font(.subheadline)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 8)
                    Capsule().fill(Color.accentColor.gradient).frame(width: geo.size.width * projection.ratio, height: 8)
                }
            }.frame(height: 8)
            if let accountName {
                Text("Funded by \(accountName)").font(.caption2).foregroundStyle(.secondary)
            }
            if !projection.isComplete {
                if let required = projection.requiredMonthly, let target = targetDate {
                    Text("Save \(CurrencyFormatter.kzt(required))/mo to reach it by \(target.formatted(.dateTime.month().year()))")
                        .font(.caption2).foregroundStyle(.orange)
                } else if let projected = projection.projectedDate {
                    Text("On track for \(projected.formatted(.dateTime.month().year())) at your current saving rate")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
