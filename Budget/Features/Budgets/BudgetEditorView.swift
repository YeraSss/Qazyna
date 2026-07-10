import SwiftUI
import SwiftData

struct BudgetEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Category> { !$0.isArchived }, sort: [SortDescriptor(\Category.sortOrder)]) private var categories: [Category]
    @Query private var existing: [CategoryBudget]

    let budget: CategoryBudget?
    @State private var categoryID: String?
    @State private var limitText = ""
    @State private var warnAt80 = true
    @State private var warnAt100 = true

    private var expenseCategories: [Category] { categories.filter { $0.kind == .expense } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $categoryID) {
                        ForEach(availableCategories) { c in Text("\(c.emoji) \(c.name)").tag(Optional(c.id)) }
                    }
                    .disabled(budget != nil)
                }
                Section("Monthly limit") {
                    HStack {
                        TextField("0", text: $limitText).keyboardType(.numberPad)
                        Text("₸")
                    }
                }
                Section {
                    Toggle("80% of limit", isOn: $warnAt80)
                    Toggle("100% of limit", isOn: $warnAt100)
                } header: {
                    Text("Warn me at")
                } footer: {
                    Text("You'll get an in-app indicator and a local notification when spending crosses a threshold.")
                }
            }
            .navigationTitle(budget == nil ? "New Budget" : "Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .onAppear(perform: load)
        }
    }

    /// When adding, only offer categories that don't already have a budget.
    private var availableCategories: [Category] {
        if budget != nil { return expenseCategories }
        let taken = Set(existing.map(\.categoryID))
        return expenseCategories.filter { !taken.contains($0.id) }
    }

    private var canSave: Bool { categoryID != nil && (Decimal(string: limitText) ?? 0) > 0 }

    private func load() {
        if let budget {
            categoryID = budget.categoryID
            limitText = NSDecimalNumber(decimal: budget.limitKZT).stringValue
            warnAt80 = budget.thresholds.contains(0.8)
            warnAt100 = budget.thresholds.contains(1.0)
        } else {
            categoryID = availableCategories.first?.id
        }
    }

    private func save() {
        guard let categoryID else { return }
        let limit = Decimal(string: limitText) ?? 0
        var thresholds: [Double] = []
        if warnAt80 { thresholds.append(0.8) }
        if warnAt100 { thresholds.append(1.0) }
        if thresholds.isEmpty { thresholds = [1.0] }
        if let budget {
            budget.limitKZT = limit
            budget.thresholds = thresholds
        } else {
            context.insert(CategoryBudget(categoryID: categoryID, limitKZT: limit, thresholds: thresholds))
        }
        try? context.save()
        BudgetAlerts.evaluate(in: context)
        Haptics.success()
        dismiss()
    }
}
