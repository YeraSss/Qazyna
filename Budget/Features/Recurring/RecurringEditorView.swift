import SwiftUI
import SwiftData

struct RecurringEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Category> { !$0.isArchived }, sort: [SortDescriptor(\Category.sortOrder)]) private var categories: [Category]
    @Query(filter: #Predicate<SubAccount> { !$0.isArchived }) private var accounts: [SubAccount]

    let rule: RecurringRule?
    @State private var title = ""
    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var categoryID: String?
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var intervalDays = 30
    @State private var nextRun = Date()
    @State private var autoLog = true

    private var account: SubAccount? { accounts.first { $0.id == accountID } }
    private var visibleCategories: [Category] { categories.filter { $0.kind == kind } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (e.g. Rent, Netflix, Salary)", text: $title)
                    Picker("Type", selection: $kind) {
                        Text("Expense").tag(TransactionKind.expense); Text("Income").tag(TransactionKind.income)
                    }.pickerStyle(.segmented)
                    HStack {
                        TextField("0", text: $amountText).keyboardType(.decimalPad)
                        Text(account?.currencyCode ?? "KZT")
                    }
                }
                Section {
                    Picker("Account", selection: $accountID) {
                        ForEach(accounts) { a in Text("\(a.bank?.name ?? "") · \(a.name)").tag(Optional(a.id)) }
                    }
                    Picker("Category", selection: $categoryID) {
                        ForEach(visibleCategories) { c in Text("\(c.emoji) \(c.name)").tag(Optional(c.id)) }
                    }
                }
                Section {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases) { Text($0.displayName).tag($0) }
                    }
                    if frequency == .custom {
                        Stepper("Every \(intervalDays) days", value: $intervalDays, in: 1...365)
                    }
                    DatePicker("Next", selection: $nextRun, displayedComponents: .date)
                    Toggle("Log automatically", isOn: $autoLog)
                } footer: {
                    Text(autoLog ? "Posts automatically on each due date." : "You'll be asked to confirm each occurrence.")
                }
            }
            .navigationTitle(rule == nil ? "New Recurring" : "Edit Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .onAppear(perform: load)
            .onChange(of: kind) { _, _ in
                if let id = categoryID, !visibleCategories.contains(where: { $0.id == id }) { categoryID = visibleCategories.first?.id }
            }
        }
    }

    private var canSave: Bool { !title.isEmpty && (Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0 && accountID != nil && categoryID != nil }

    private func load() {
        if let rule {
            title = rule.title; kind = rule.kind
            amountText = NSDecimalNumber(decimal: rule.amountOriginal).stringValue
            accountID = rule.accountID; categoryID = rule.categoryID
            frequency = rule.frequency; intervalDays = rule.intervalDays ?? 30
            nextRun = rule.nextRun; autoLog = rule.autoLog
        } else {
            accountID = accounts.first?.id
            categoryID = visibleCategories.first?.id
        }
    }

    private func save() {
        guard let accountID, let categoryID, let account else { return }
        let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        if let rule {
            rule.title = title; rule.kind = kind; rule.amountOriginal = amount
            rule.currencyCode = account.currencyCode
            rule.accountID = accountID; rule.categoryID = categoryID
            rule.frequency = frequency; rule.intervalDays = frequency == .custom ? intervalDays : nil
            rule.nextRun = nextRun; rule.autoLog = autoLog
        } else {
            context.insert(RecurringRule(title: title, kind: kind, amountOriginal: amount,
                currencyCode: account.currencyCode, accountID: accountID, categoryID: categoryID,
                frequency: frequency, intervalDays: frequency == .custom ? intervalDays : nil,
                nextRun: nextRun, autoLog: autoLog))
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
