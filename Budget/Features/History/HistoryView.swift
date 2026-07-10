import SwiftUI
import SwiftData

struct TxnFilter: Equatable {
    var kind: TransactionKind?
    var categoryID: String?
    var accountID: UUID?

    var isActive: Bool { kind != nil || categoryID != nil || accountID != nil }
}

/// Scrollable transaction history grouped by day, with search and filters by type, category,
/// and account. Swipe to edit/delete. Filtering is done in-memory over a reverse-date query —
/// fine for typical personal volumes (pagination is a future optimization).
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateService

    @Query(sort: [SortDescriptor(\TransactionRecord.date, order: .reverse)])
    private var transactions: [TransactionRecord]
    @Query private var categories: [Category]
    @Query private var accounts: [SubAccount]

    @State private var searchText = ""
    @State private var filter = TxnFilter()
    @State private var showFilter = false
    @State private var editing: TransactionRecord?

    /// External deep-link filter (e.g. tapped a chart segment) applied on appear.
    var initialFilter: TxnFilter?

    private var categoryMap: [String: Category] { Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var accountMap: [UUID: SubAccount] { Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    private var filtered: [TransactionRecord] {
        transactions.filter { tx in
            if let k = filter.kind, tx.kind != k { return false }
            if let c = filter.categoryID, tx.categoryID != c { return false }
            if let a = filter.accountID, tx.accountID != a { return false }
            if !searchText.isEmpty {
                let hay = "\(tx.merchant ?? "") \(tx.note ?? "") \(categoryMap[tx.categoryID]?.name ?? "")".lowercased()
                if !hay.contains(searchText.lowercased()) { return false }
            }
            return true
        }
    }

    private var grouped: [(day: Int, items: [TransactionRecord])] {
        Dictionary(grouping: filtered, by: \.dateKey)
            .map { (day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            Group {
                if grouped.isEmpty {
                    ContentUnavailableView(transactions.isEmpty ? "No transactions yet" : "No matches",
                                           systemImage: "list.bullet.rectangle",
                                           description: Text(transactions.isEmpty
                                               ? "Add your first expense or income with the + button."
                                               : "Try adjusting your search or filters."))
                } else {
                    List {
                        ForEach(grouped, id: \.day) { group in
                            Section {
                                ForEach(group.items) { tx in
                                    TransactionRow(tx: tx, category: categoryMap[tx.categoryID], account: accountMap[tx.accountID])
                                        .contentShape(Rectangle())
                                        .onTapGesture { editing = tx }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { delete(tx) } label: { Label("Delete", systemImage: "trash") }
                                            Button { editing = tx } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                                        }
                                }
                            } header: {
                                dayHeader(day: group.day, items: group.items)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search merchant, note, category")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilter = true } label: {
                        Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilter) {
                HistoryFilterView(filter: $filter, categories: categories, accounts: accounts)
            }
            .sheet(item: $editing) { QuickAddView(editing: $0) }
            .onAppear { if let f = initialFilter { filter = f } }
        }
    }

    private func dayHeader(day: Int, items: [TransactionRecord]) -> some View {
        let expense = items.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amountKZT }
        return HStack {
            Text(dayString(day))
            Spacer()
            if expense > 0 { Text("−\(CurrencyFormatter.kzt(expense))").foregroundStyle(.secondary) }
        }
    }

    private func dayString(_ dayKey: Int) -> String {
        var c = DateComponents()
        c.year = dayKey / 10_000; c.month = (dayKey / 100) % 100; c.day = dayKey % 100
        let date = Calendar.current.date(from: c) ?? Date()
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func delete(_ tx: TransactionRecord) {
        try? Ledger.delete(tx, in: context)
        Haptics.tap()
    }
}

/// A single transaction row.
struct TransactionRow: View {
    let tx: TransactionRecord
    let category: Category?
    let account: SubAccount?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: category?.colorHex ?? "#90A4AE").opacity(0.22)).frame(width: 40, height: 40)
                Text(category?.emoji ?? "📦")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.merchant ?? category?.name ?? "Transaction")
                    .font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(category?.name ?? tx.categoryID).font(.caption2).foregroundStyle(.secondary)
                    if let account { Text("· \(account.name)").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    if tx.needsReview {
                        Text("Review").font(.caption2.bold()).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(signedAmount)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tx.kind == .expense ? .primary : Color.green)
                if tx.currencyCode != Money.baseCurrency {
                    Text(CurrencyFormatter.kzt(tx.amountKZT)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var signedAmount: String {
        let prefix = tx.kind == .expense ? "−" : "+"
        return prefix + CurrencyFormatter.string(tx.amountOriginal, currencyCode: tx.currencyCode)
    }
}
