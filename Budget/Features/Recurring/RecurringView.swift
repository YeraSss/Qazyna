import SwiftUI
import SwiftData

struct RecurringView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\RecurringRule.nextRun)]) private var rules: [RecurringRule]
    @Query private var categories: [Category]
    @Query private var accounts: [SubAccount]
    @State private var editing: RecurringRule?
    @State private var adding = false

    private var due: [RecurringRule] { rules.filter { $0.isActive && !$0.autoLog && $0.nextRun <= Date() } }
    private var scheduled: [RecurringRule] { rules.filter { !($0.isActive && !$0.autoLog && $0.nextRun <= Date()) } }
    private var categoryMap: [String: Category] { Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView("No recurring items", systemImage: "repeat",
                                       description: Text("Add rent, subscriptions, or salary to auto-log them on schedule."))
            }
            if !due.isEmpty {
                Section("Due now") {
                    ForEach(due) { rule in
                        RecurringRow(rule: rule, category: categoryMap[rule.categoryID])
                        HStack {
                            Button { RecurringScheduler.confirm(rule, in: context); Haptics.success() } label: {
                                Label("Log now", systemImage: "checkmark.circle.fill")
                            }.buttonStyle(.borderedProminent).controlSize(.small)
                            Button { RecurringScheduler.skip(rule, in: context) } label: { Text("Skip") }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
            Section("Scheduled") {
                ForEach(scheduled) { rule in
                    RecurringRow(rule: rule, category: categoryMap[rule.categoryID])
                        .contentShape(Rectangle())
                        .onTapGesture { editing = rule }
                        .swipeActions {
                            Button(role: .destructive) { context.delete(rule); try? context.save() } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
        }
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { RecurringEditorView(rule: nil) }
        .sheet(item: $editing) { RecurringEditorView(rule: $0) }
    }
}

struct RecurringRow: View {
    let rule: RecurringRule
    let category: Category?
    var body: some View {
        HStack(spacing: 12) {
            Text(category?.emoji ?? (rule.kind == .income ? "💰" : "🔁")).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title).font(.subheadline.weight(.medium))
                Text("\(rule.frequency.displayName) · next \(rule.nextRun.formatted(.dateTime.month().day()))\(rule.autoLog ? " · auto" : "")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text((rule.kind == .expense ? "−" : "+") + CurrencyFormatter.string(rule.amountOriginal, currencyCode: rule.currencyCode))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(rule.kind == .expense ? .primary : Color.green)
        }
        .padding(.vertical, 2)
    }
}
