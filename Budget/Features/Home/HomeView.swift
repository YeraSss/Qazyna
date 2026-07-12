import SwiftUI
import SwiftData

/// Home overview: this month's spending/income, net worth, quick add, and recent activity.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateService
    @EnvironmentObject private var privacy: PrivacyManager

    @Query private var monthlyRollups: [MonthlyRollup]
    @Query(filter: #Predicate<SubAccount> { !$0.isArchived }) private var accounts: [SubAccount]
    @Query private var categories: [Category]
    @Query(sort: [SortDescriptor(\TransactionRecord.date, order: .reverse)]) private var allTx: [TransactionRecord]

    @State private var showQuickAdd = false
    @State private var showScan = false
    @State private var showImport = false
    @State private var editing: TransactionRecord?

    private let monthKey = DateKeys.currentMonthKey()
    private var currentMonth: MonthlyRollup? { monthlyRollups.first { $0.monthKey == monthKey } }
    private var categoryMap: [String: Category] { Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var accountMap: [UUID: SubAccount] { Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var recent: [TransactionRecord] { Array(allTx.prefix(8)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthCard
                    netWorthRow
                    quickAddButton
                    recentSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Date().formatted(.dateTime.month(.wide).year()))
            .toolbar {
                if privacy.enabled {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { privacy.toggleReveal() } label: { Image(systemName: privacy.eyeSymbol) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showQuickAdd = true } label: { Label("Quick add", systemImage: "plus") }
                        Button { showScan = true } label: { Label("Scan receipt", systemImage: "doc.text.viewfinder") }
                        Button { showImport = true } label: { Label("Import CSV", systemImage: "square.and.arrow.down") }
                    } label: { Image(systemName: "plus.circle.fill") }
                }
            }
            .sheet(isPresented: $showQuickAdd) { QuickAddView() }
            .sheet(isPresented: $showScan) { ReceiptScanView() }
            .sheet(isPresented: $showImport) { ImportView() }
            .sheet(item: $editing) { QuickAddView(editing: $0) }
        }
    }

    private var monthCard: some View {
        let expense = currentMonth?.expenseKZT ?? 0
        let income = currentMonth?.incomeKZT ?? 0
        return VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Spent this month").font(.subheadline).foregroundStyle(.secondary)
                Text(CurrencyFormatter.kzt(expense))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .contentTransition(.numericText()).animation(.snappy, value: expense)
                    .hideBalance(privacy.isHidden)
            }
            HStack {
                summaryPill(title: "Income", value: income, color: .green, icon: "arrow.down.left")
                summaryPill(title: "Net", value: income - expense, color: income - expense >= 0 ? .green : .red, icon: "equal")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func summaryPill(title: String, value: Decimal, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(CurrencyFormatter.kzt(value)).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .hideBalance(privacy.isHidden)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
    }

    private var netWorthRow: some View {
        let total = NetWorthCalculator.total(accounts, rateToKZT: { fx.rateToKZT($0) })
        return HStack {
            Image(systemName: "building.columns.fill").foregroundStyle(.tint)
            Text("Net worth")
            Spacer()
            Text(CurrencyFormatter.kzt(total)).fontWeight(.semibold)
                .hideBalance(privacy.isHidden)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var quickAddButton: some View {
        Button { Haptics.tap(); showQuickAdd = true } label: {
            Label("Add Transaction", systemImage: "plus")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent").font(.headline).padding(.horizontal, 4)
            if recent.isEmpty {
                Text("No transactions yet.").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { tx in
                        TransactionRow(tx: tx, category: categoryMap[tx.categoryID], account: accountMap[tx.accountID])
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = tx }
                        if tx.id != recent.last?.id { Divider().padding(.leading, 14) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }
        }
    }
}
