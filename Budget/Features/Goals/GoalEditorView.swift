import SwiftUI
import SwiftData

struct GoalEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [SubAccount]

    let goal: SavingsGoal?
    @State private var name = ""
    @State private var targetText = ""
    @State private var linkedAccountID: UUID?
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal name (e.g. Emergency fund)", text: $name)
                    HStack {
                        Text("Target")
                        TextField("0", text: $targetText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        Text("₸")
                    }
                }
                Section {
                    Picker("Account", selection: $linkedAccountID) {
                        Text("Track manually").tag(UUID?.none)
                        ForEach(accounts) { a in Text("\(a.bank?.name ?? "") · \(a.name)").tag(UUID?.some(a.id)) }
                    }
                } header: {
                    Text("Funded by")
                } footer: {
                    Text("Linking an account tracks its balance toward the goal. Deposits/savings work best.")
                }
                Section {
                    Toggle("Target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("By", selection: $targetDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty || (Decimal(string: targetText) ?? 0) <= 0)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let goal {
            name = goal.name
            targetText = NSDecimalNumber(decimal: goal.targetKZT).stringValue
            linkedAccountID = goal.linkedAccountID
            if let d = goal.targetDate { hasTargetDate = true; targetDate = d }
        }
    }

    private func save() {
        let target = Decimal(string: targetText) ?? 0
        if let goal {
            goal.name = name; goal.targetKZT = target
            goal.linkedAccountID = linkedAccountID
            goal.targetDate = hasTargetDate ? targetDate : nil
        } else {
            context.insert(SavingsGoal(name: name, targetKZT: target, linkedAccountID: linkedAccountID,
                                       targetDate: hasTargetDate ? targetDate : nil))
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
