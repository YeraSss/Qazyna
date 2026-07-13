import SwiftUI
import SwiftData

/// The "Wealth" screen: grand-total net worth across all banks, each bank expandable to its
/// sub-accounts (card / deposit / savings / cash / asset / loan). The net-worth differentiator.
struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateService
    @EnvironmentObject private var privacy: PrivacyManager

    @Query(sort: [SortDescriptor(\Bank.sortOrder)]) private var banks: [Bank]
    @Query(filter: #Predicate<SubAccount> { !$0.isArchived }) private var accounts: [SubAccount]

    @State private var expanded: Set<String> = []
    @State private var showAddBank = false
    @State private var showTransfer = false
    @State private var editingBank: Bank?
    @State private var addingAccountToBank: Bank?
    @State private var editingAccount: SubAccount?
    @State private var adjustingAccount: SubAccount?

    private var rate: (String) -> Decimal { { fx.rateToKZT($0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    netWorthHeader
                    ForEach(banks) { bank in
                        bankCard(bank)
                    }
                    if banks.isEmpty {
                        ContentUnavailableView("No banks yet",
                                               systemImage: "building.columns",
                                               description: Text("Add a bank to start tracking your balances."))
                            .padding(.top, 40)
                    }
                    addBankButton
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Accounts")
            .toolbar {
                if privacy.enabled {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { privacy.toggleReveal() } label: { Image(systemName: privacy.eyeSymbol) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Haptics.tap(); showTransfer = true } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .disabled(accounts.count < 2)
                }
            }
            .sheet(isPresented: $showAddBank) { BankEditorView(bank: nil) }
            .sheet(item: $editingBank) { BankEditorView(bank: $0) }
            .sheet(item: $addingAccountToBank) { SubAccountEditorView(bank: $0, account: nil) }
            .sheet(item: $editingAccount) { acct in
                SubAccountEditorView(bank: acct.bank, account: acct)
            }
            .sheet(item: $adjustingAccount) { AdjustBalanceView(account: $0) }
            .sheet(isPresented: $showTransfer) { TransferView(accounts: accounts) }
        }
    }

    // MARK: Net-worth header

    private var netWorthHeader: some View {
        let total = NetWorthCalculator.total(accounts, rateToKZT: rate)
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("Net Worth").font(.subheadline).foregroundStyle(.secondary)
                if privacy.enabled {
                    Image(systemName: privacy.eyeSymbol).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(privacy.masked(CurrencyFormatter.kzt(total)))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: total)
            if fx.isStale {
                Label(fx.ratesAsOfText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture { privacy.toggleReveal() }
    }

    // MARK: Bank card

    private func bankCard(_ bank: Bank) -> some View {
        let isOpen = expanded.contains(bank.id)
        let subs = bank.subAccounts
            .filter { !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
        let bankTotal = NetWorthCalculator.bankTotal(bank, rateToKZT: rate)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.28)) {
                    if isOpen { expanded.remove(bank.id) } else { expanded.insert(bank.id) }
                }
                Haptics.selection()
            } label: {
                HStack(spacing: 12) {
                    BankLogoView(bank: bank)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bank.name).font(.headline)
                        Text("\(subs.count) account\(subs.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(privacy.masked(CurrencyFormatter.kzt(bankTotal)))
                        .font(.headline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(subs) { sub in
                        Divider().padding(.leading, 14)
                        subAccountRow(sub)
                    }
                    Divider().padding(.leading, 14)
                    Button {
                        Haptics.tap(); addingAccountToBank = bank
                    } label: {
                        Label("Add sub-account", systemImage: "plus.circle")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .contextMenu {
            Button { editingBank = bank } label: { Label("Edit bank", systemImage: "pencil") }
            Button { addingAccountToBank = bank } label: { Label("Add sub-account", systemImage: "plus") }
            Button(role: .destructive) { deleteBank(bank) } label: { Label("Delete bank", systemImage: "trash") }
        }
    }

    private func subAccountRow(_ sub: SubAccount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sub.type.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(sub.name).font(.subheadline.weight(.medium))
                Text(sub.type.displayName)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(privacy.masked(CurrencyFormatter.string(sub.cachedBalance, currencyCode: sub.currencyCode)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(sub.type.isLiability ? .red : .primary)
                if sub.currencyCode != Money.baseCurrency {
                    Text(privacy.masked("≈ \(CurrencyFormatter.kzt(Money.roundedKZT(sub.cachedBalance * rate(sub.currencyCode))))"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .contentShape(Rectangle())
        .contextMenu {
            Button { adjustingAccount = sub } label: { Label("Adjust balance", systemImage: "slider.horizontal.3") }
            Button { editingAccount = sub } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { deleteAccount(sub) } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions {
            Button { adjustingAccount = sub } label: { Label("Adjust", systemImage: "slider.horizontal.3") }
                .tint(.blue)
        }
    }

    private var addBankButton: some View {
        Button {
            Haptics.tap(); showAddBank = true
        } label: {
            Label("Add Bank", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 6)
    }

    // MARK: Actions

    private func deleteBank(_ bank: Bank) {
        // Rebuild balances/rollups after a cascade delete so derived data stays correct.
        context.delete(bank)
        try? context.save()
        try? Ledger.rebuildBalances(in: context)
        try? Ledger.rebuildRollups(in: context)
    }

    private func deleteAccount(_ sub: SubAccount) {
        context.delete(sub)
        try? context.save()
        try? Ledger.rebuildRollups(in: context)
    }
}
