import SwiftUI
import SwiftData

/// Drill-down list: all transactions for a category in a given month (from tapping a chart
/// segment / legend row). No own NavigationStack — pushed onto the Analytics stack.
struct CategoryTransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query private var transactions: [TransactionRecord]
    @Query private var categories: [Category]
    @Query private var accounts: [SubAccount]
    @State private var editing: TransactionRecord?

    let title: String

    init(monthKey: Int, categoryID: String, title: String) {
        self.title = title
        _transactions = Query(
            filter: #Predicate<TransactionRecord> { $0.monthKey == monthKey && $0.categoryID == categoryID },
            sort: [SortDescriptor(\.date, order: .reverse)]
        )
    }

    private var categoryMap: [String: Category] { Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var accountMap: [UUID: SubAccount] { Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var total: Decimal { transactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountKZT } }

    var body: some View {
        List {
            Section {
                ForEach(transactions) { tx in
                    TransactionRow(tx: tx, category: categoryMap[tx.categoryID], account: accountMap[tx.accountID])
                        .contentShape(Rectangle())
                        .onTapGesture { editing = tx }
                        .swipeActions {
                            Button(role: .destructive) { try? Ledger.delete(tx, in: context) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            } header: {
                Text("\(transactions.count) transactions · \(CurrencyFormatter.kzt(total))")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { QuickAddView(editing: $0) }
    }
}
