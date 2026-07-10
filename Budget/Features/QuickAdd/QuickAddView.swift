import SwiftUI
import SwiftData

/// Fast add / edit for a single transaction. Designed for sub-5-second entry: large amount,
/// expense/income toggle, category grid, account, date, note. Snapshots the KZT rate at entry.
struct QuickAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fx: FXRateService

    @Query(filter: #Predicate<Category> { !$0.isArchived },
           sort: [SortDescriptor(\Category.sortOrder)]) private var categories: [Category]
    @Query(filter: #Predicate<SubAccount> { !$0.isArchived },
           sort: [SortDescriptor(\SubAccount.sortOrder)]) private var accounts: [SubAccount]

    /// Existing transaction when editing; nil when adding.
    var editing: TransactionRecord?
    /// Pre-filled values from OCR / import to seed a new entry.
    var prefill: ParsedEntry?

    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var categoryID: String?
    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var merchant = ""
    @State private var quickText = ""
    @State private var parsing = false

    private var visibleCategories: [Category] { categories.filter { $0.kind == kind } }
    private var account: SubAccount? { accounts.first { $0.id == accountID } }
    private var amount: Decimal { Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var canSave: Bool { amount > 0 && categoryID != nil && accountID != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if editing == nil { nlBar }
                    kindPicker
                    amountDisplay
                    categoryGrid
                    detailsCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(editing == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    /// Natural-language entry: type "coffee 1500 kaspi" and it fills the fields below.
    private var nlBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.tint)
            TextField("Type it — e.g. “coffee 1500 kaspi”", text: $quickText)
                .submitLabel(.go)
                .onSubmit(runParse)
            if parsing {
                ProgressView()
            } else {
                Button(action: runParse) { Image(systemName: "wand.and.stars") }
                    .disabled(quickText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func runParse() {
        let text = quickText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        parsing = true
        Task {
            let entry = await NLParser.parseSmart(text, in: context)
            await MainActor.run { apply(entry); parsing = false }
        }
    }

    /// Apply a parsed entry to the form fields (from NL text or OCR).
    func apply(_ e: ParsedEntry) {
        kind = e.kind
        if let a = e.amount { amountText = NSDecimalNumber(decimal: a).stringValue }
        if let c = e.categoryID, visibleCategories.contains(where: { $0.id == c }) { categoryID = c }
        else { categoryID = visibleCategories.first?.id }
        if let acc = e.accountID { accountID = acc }
        if let m = e.merchant, !m.isEmpty { merchant = m }
        Haptics.success()
    }

    private var kindPicker: some View {
        Picker("Type", selection: $kind) {
            Text("Expense").tag(TransactionKind.expense)
            Text("Income").tag(TransactionKind.income)
        }
        .pickerStyle(.segmented)
        .onChange(of: kind) { _, _ in
            // Keep the selected category valid for the chosen kind.
            if let id = categoryID, !visibleCategories.contains(where: { $0.id == id }) {
                categoryID = visibleCategories.first?.id
            }
            Haptics.selection()
        }
    }

    private var amountDisplay: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(kind == .expense ? .primary : Color.green)
                    .fixedSize()
                Text(account?.currencyCode ?? Money.baseCurrency)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let account, account.currencyCode != Money.baseCurrency, amount > 0 {
                Text("≈ \(CurrencyFormatter.kzt(fx.convertToKZT(amount, from: account.currencyCode)))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
            ForEach(visibleCategories) { cat in
                CategoryChip(category: cat, isSelected: categoryID == cat.id)
                    .onTapGesture { categoryID = cat.id; Haptics.selection() }
            }
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            Picker(selection: $accountID) {
                ForEach(accounts) { acct in
                    Text("\(acct.bank?.name ?? "") · \(acct.name)").tag(Optional(acct.id))
                }
            } label: { Label("Account", systemImage: "building.columns") }
                .padding(.horizontal, 14).padding(.vertical, 6)
            Divider()
            DatePicker(selection: $date, displayedComponents: [.date, .hourAndMinute]) {
                Label("Date", systemImage: "calendar")
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            Divider()
            HStack {
                Label("Merchant", systemImage: "storefront")
                TextField("optional", text: $merchant).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            HStack {
                Label("Note", systemImage: "text.alignleft")
                TextField("optional", text: $note).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    private func load() {
        if let tx = editing {
            kind = tx.kind
            amountText = NSDecimalNumber(decimal: tx.amountOriginal).stringValue
            categoryID = tx.categoryID
            accountID = tx.accountID
            date = tx.date
            note = tx.note ?? ""
            merchant = tx.merchant ?? ""
        } else {
            accountID = accounts.first?.id
            categoryID = visibleCategories.first?.id
            if let prefill { apply(prefill) }
        }
    }

    private func save() {
        guard let account, let categoryID else { return }
        let rate = fx.rateToKZT(account.currencyCode)
        let draft = TransactionDraft(
            id: editing?.id,
            dedupKey: editing?.dedupKey,
            kind: kind,
            amountOriginal: amount,
            currencyCode: account.currencyCode,
            fxRateToKZT: rate,
            date: date,
            accountID: account.id,
            categoryID: categoryID,
            merchant: merchant.isEmpty ? nil : merchant,
            note: note.isEmpty ? nil : note,
            source: editing?.source ?? .manual,
            needsReview: false
        )
        do {
            if let tx = editing {
                try Ledger.update(tx, with: draft, in: context)
                // If the user corrected the category of a captured merchant, teach the mapping.
                if let m = draft.merchant { MerchantLearning.learn(merchant: m, categoryID: categoryID, in: context) }
            } else {
                try Ledger.insert(draft, in: context)
            }
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
        }
    }
}

/// A selectable category tile.
struct CategoryChip: View {
    let category: Category
    let isSelected: Bool
    var body: some View {
        VStack(spacing: 5) {
            Text(category.emoji).font(.title2)
            Text(category.name)
                .font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color(hex: category.colorHex).opacity(0.25) : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color(hex: category.colorHex) : .clear, lineWidth: 2)
        )
    }
}
