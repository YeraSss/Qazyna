import SwiftUI
import SwiftData

/// Inbox for transactions captured by Tap to Track that still need a category (and possibly a
/// corrected bank/amount). Each item shows the auto-detected amount + bank; tapping a category
/// chip files it in one tap (and teaches the merchant → category mapping for next time).
struct ReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<TransactionRecord> { $0.needsReview },
           sort: [SortDescriptor(\TransactionRecord.date, order: .reverse)])
    private var items: [TransactionRecord]
    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.sortOrder)]) private var categories: [Category]
    @Query private var accounts: [SubAccount]

    @State private var editing: TransactionRecord?

    private var expenseCategories: [Category] { categories.filter { $0.kind == .expense } }
    private func account(_ id: UUID) -> SubAccount? { accounts.first { $0.id == id } }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("All caught up",
                                           systemImage: "checkmark.circle",
                                           description: Text("Tapped payments you still need to categorize will appear here."))
                } else {
                    List {
                        ForEach(items) { tx in
                            reviewItem(tx)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Review taps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { QuickAddView(editing: $0) }
        }
    }

    @ViewBuilder private func reviewItem(_ tx: TransactionRecord) -> some View {
        let acct = account(tx.accountID)
        let bankColor = Color(hex: acct?.bank?.brandColorHex ?? "#8E8E93")
        Section {
            // Detected amount + merchant + bank.
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tx.merchant ?? "Apple Pay").font(.headline)
                    HStack(spacing: 6) {
                        if let acct {
                            Text("\(acct.bank?.name ?? "") · \(acct.name)")
                                .font(.caption).foregroundStyle(bankColor)
                        }
                        Text(tx.date.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(CurrencyFormatter.string(tx.amountOriginal, currencyCode: tx.currencyCode))
                    .font(.title3.weight(.bold))
            }
            .padding(.vertical, 2)

            // One-tap category chips.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(expenseCategories) { cat in
                        Button { categorize(tx, as: cat) } label: {
                            CategoryChip(category: cat, isSelected: tx.categoryID == cat.id)
                                .frame(width: 76)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Button { editing = tx } label: {
                Label("Edit amount, bank or date", systemImage: "pencil").font(.subheadline)
            }
        }
    }

    private func categorize(_ tx: TransactionRecord, as category: Category) {
        try? Ledger.recategorize(tx, to: category.id, in: context)
        if let merchant = tx.merchant, !merchant.isEmpty {
            MerchantLearning.learn(merchant: merchant, categoryID: category.id, in: context)
        }
        Haptics.success()
    }
}
