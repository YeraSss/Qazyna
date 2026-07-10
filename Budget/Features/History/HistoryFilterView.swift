import SwiftUI

/// Filter sheet for History: by type, category, and account.
struct HistoryFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: TxnFilter
    let categories: [Category]
    let accounts: [SubAccount]

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: Binding(
                        get: { filter.kind },
                        set: { filter.kind = $0 })) {
                        Text("All").tag(TransactionKind?.none)
                        Text("Expense").tag(TransactionKind?.some(.expense))
                        Text("Income").tag(TransactionKind?.some(.income))
                    }
                    .pickerStyle(.segmented)
                }
                Section("Category") {
                    Picker("Category", selection: Binding(
                        get: { filter.categoryID },
                        set: { filter.categoryID = $0 })) {
                        Text("All").tag(String?.none)
                        ForEach(categories.sorted { $0.sortOrder < $1.sortOrder }) { c in
                            Text("\(c.emoji) \(c.name)").tag(String?.some(c.id))
                        }
                    }
                }
                Section("Account") {
                    Picker("Account", selection: Binding(
                        get: { filter.accountID },
                        set: { filter.accountID = $0 })) {
                        Text("All").tag(UUID?.none)
                        ForEach(accounts) { a in
                            Text("\(a.bank?.name ?? "") · \(a.name)").tag(UUID?.some(a.id))
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { filter = TxnFilter() }.disabled(!filter.isActive)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
