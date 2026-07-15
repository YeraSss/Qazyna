import SwiftUI
import SwiftData

// MARK: - Bank editor

struct BankEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Bank.sortOrder)]) private var banks: [Bank]

    let bank: Bank?
    @State private var name = ""
    @State private var color: Color = .blue
    @State private var domain = ""   // website — used to fetch the bank's logo

    var body: some View {
        NavigationStack {
            Form {
                if bank == nil {
                    Section("Quick add") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(SeedData.bankPresets) { preset in
                                    Button {
                                        name = preset.name
                                        color = Color(hex: preset.color)
                                        domain = preset.domain   // enables the real logo
                                        Haptics.selection()
                                    } label: {
                                        VStack(spacing: 6) {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(hex: preset.color).gradient)
                                                .frame(width: 48, height: 48)
                                                .overlay(Text(initials(preset.name)).font(.headline.bold())
                                                    .foregroundStyle(Color(hex: preset.color).readableForeground))
                                            Text(preset.name).font(.caption2).foregroundStyle(.primary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Section {
                    TextField("Name", text: $name)
                    ColorPicker("Brand color", selection: $color, supportsOpacity: false)
                    HStack {
                        Label("Website", systemImage: "globe")
                        TextField("e.g. kaspi.kz", text: $domain)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Text("Preview")
                        Spacer()
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(color.gradient)
                            .frame(width: 44, height: 44)
                            .overlay(Text(monogram).font(.headline.bold())
                                .foregroundStyle(color.readableForeground))
                    }
                } header: {
                    Text("Bank")
                } footer: {
                    Text("Add the bank's website so Qazyna can show its real logo. Without it, a brand-colored monogram is used.")
                }
            }
            .navigationTitle(bank == nil ? "Add Bank" : "Edit Bank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let bank {
                    name = bank.name
                    color = Color(hex: bank.brandColorHex)
                    domain = bank.domain
                }
            }
        }
    }

    private var monogram: String { initials(name) }

    private func initials(_ value: String) -> String {
        let letters = value.split(separator: " ").prefix(2).compactMap { $0.first }
        let text = String(letters).uppercased()
        return text.isEmpty ? "?" : text
    }

    /// Normalize a typed website into a bare domain (strip scheme/www/path), lowercased.
    private func normalizedDomain(_ raw: String) -> String {
        var d = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://", "www."] where d.hasPrefix(prefix) { d.removeFirst(prefix.count) }
        if let slash = d.firstIndex(of: "/") { d = String(d[..<slash]) }
        return d
    }

    private func save() {
        let hex = color.hexString()
        let cleanDomain = normalizedDomain(domain)
        if let bank {
            bank.name = name
            bank.brandColorHex = hex
            bank.domain = cleanDomain
        } else {
            let new = Bank(id: UUID().uuidString, name: name, domain: cleanDomain,
                           brandColorHex: hex, sortOrder: (banks.map(\.sortOrder).max() ?? 0) + 1)
            context.insert(new)
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - Sub-account editor

struct SubAccountEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fx: FXRateService

    let bank: Bank?
    let account: SubAccount?

    @State private var name = ""
    @State private var type: AccountType = .card
    @State private var currency = Money.baseCurrency
    @State private var openingBalanceText = ""
    @State private var includeInNetWorth = true

    private var hasTransactions: Bool { !(account?.transactions.isEmpty ?? true) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { t in
                            Label(t.displayName, systemImage: t.systemImage).tag(t)
                        }
                    }
                    CurrencyPicker(selection: $currency)
                        .disabled(hasTransactions)
                }
                Section {
                    HStack {
                        Text(account == nil ? "Opening balance" : "Balance")
                        Spacer()
                        TextField("0", text: $openingBalanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(currency)
                    }
                    Toggle("Include in net worth", isOn: $includeInNetWorth)
                } footer: {
                    if hasTransactions {
                        Text("Currency can't change once transactions exist. Editing the balance records a manual adjustment.")
                    }
                }
            }
            .navigationTitle(account == nil ? "Add Sub-account" : "Edit Sub-account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let account {
            name = account.name
            type = account.type
            currency = account.currencyCode
            includeInNetWorth = account.includeInNetWorth
            openingBalanceText = NSDecimalNumber(decimal: account.cachedBalance).stringValue
        }
    }

    private func save() {
        let value = Decimal(string: openingBalanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
        if let account {
            account.name = name
            account.type = type
            account.includeInNetWorth = includeInNetWorth
            if !hasTransactions { account.currencyCode = currency }
            // Editing the shown balance records an explicit adjustment (preserves invariant).
            if value != account.cachedBalance {
                try? Ledger.adjustBalance(account, to: value, reason: "Manual edit", in: context)
            }
        } else {
            let new = SubAccount(name: name, type: type, currencyCode: currency,
                                 openingBalance: value, includeInNetWorth: includeInNetWorth,
                                 sortOrder: (bank?.subAccounts.map(\.sortOrder).max() ?? 0) + 1)
            new.bank = bank
            context.insert(new)
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - Adjust balance

struct AdjustBalanceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let account: SubAccount
    @State private var targetText = ""
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Current balance") {
                    Text(CurrencyFormatter.string(account.cachedBalance, currencyCode: account.currencyCode))
                        .font(.title3.weight(.semibold))
                }
                Section("New balance") {
                    HStack {
                        TextField("0", text: $targetText).keyboardType(.decimalPad)
                        Text(account.currencyCode)
                    }
                    TextField("Reason (optional)", text: $reason)
                }
            }
            .navigationTitle("Adjust Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(targetText.isEmpty)
                }
            }
            .onAppear { targetText = NSDecimalNumber(decimal: account.cachedBalance).stringValue }
        }
    }

    private func save() {
        let target = Decimal(string: targetText.replacingOccurrences(of: ",", with: ".")) ?? account.cachedBalance
        try? Ledger.adjustBalance(account, to: target, reason: reason.isEmpty ? nil : reason, in: context)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Transfer

struct TransferView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fx: FXRateService
    let accounts: [SubAccount]

    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var amountText = ""
    @State private var toAmountText = ""
    @State private var note = ""

    private var from: SubAccount? { accounts.first { $0.id == fromID } }
    private var to: SubAccount? { accounts.first { $0.id == toID } }
    private var crossCurrency: Bool { (from?.currencyCode ?? "") != (to?.currencyCode ?? "") }

    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    accountPicker(selection: $fromID, exclude: toID)
                }
                Section("To") {
                    accountPicker(selection: $toID, exclude: fromID)
                }
                Section("Amount") {
                    HStack {
                        TextField("0", text: $amountText).keyboardType(.decimalPad)
                            .onChange(of: amountText) { _, _ in syncToAmount() }
                        Text(from?.currencyCode ?? "")
                    }
                    if crossCurrency {
                        HStack {
                            Text("Received")
                            Spacer()
                            TextField("0", text: $toAmountText).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text(to?.currencyCode ?? "")
                        }
                    }
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transfer") { save() }.disabled(!isValid)
                }
            }
            .onAppear {
                fromID = accounts.first?.id
                toID = accounts.dropFirst().first?.id
            }
        }
    }

    private func accountPicker(selection: Binding<UUID?>, exclude: UUID?) -> some View {
        Picker("Account", selection: selection) {
            ForEach(accounts.filter { $0.id != exclude }) { acct in
                Text("\(acct.bank?.name ?? "") · \(acct.name)").tag(Optional(acct.id))
            }
        }
    }

    private var isValid: Bool {
        guard from != nil, to != nil, fromID != toID else { return false }
        let amt = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return amt > 0
    }

    private func syncToAmount() {
        guard crossCurrency, let from, let to else { return }
        let amt = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        // Convert via KZT: fromCur → KZT → toCur.
        let kzt = amt * fx.rateToKZT(from.currencyCode)
        let converted = kzt / fx.rateToKZT(to.currencyCode)
        toAmountText = NSDecimalNumber(decimal: Money.rounded(converted, fractionDigits: Money.fractionDigits(for: to.currencyCode))).stringValue
    }

    private func save() {
        guard let from, let to else { return }
        let amt = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let toAmt = crossCurrency
            ? (Decimal(string: toAmountText.replacingOccurrences(of: ",", with: ".")) ?? amt)
            : amt
        let draft = TransferDraft(fromAccountID: from.id, toAccountID: to.id,
                                  fromAmount: amt, fromCurrencyCode: from.currencyCode,
                                  toAmount: toAmt, toCurrencyCode: to.currencyCode,
                                  note: note.isEmpty ? nil : note)
        try? Ledger.transfer(draft, in: context)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Shared currency picker

struct CurrencyPicker: View {
    @EnvironmentObject private var fx: FXRateService
    @Binding var selection: String

    var body: some View {
        Picker("Currency", selection: $selection) {
            ForEach(codes, id: \.self) { Text($0).tag($0) }
        }
    }

    private var codes: [String] {
        var set = Set(fx.supportedCurrencyCodes)
        set.formUnion(["KZT", "USD", "EUR", "RUB"])
        // KZT first, then alphabetical.
        let rest = set.subtracting(["KZT"]).sorted()
        return ["KZT"] + rest
    }
}

// MARK: - Color → hex

extension Color {
    func hexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
