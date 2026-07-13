import SwiftUI
import SwiftData

/// Guided setup for Tap to Track. Because iOS does not allow apps to install personal
/// automations programmatically, this screen walks the user through building it once, and
/// lets them map each Wallet card to a sub-account so taps land in the right place.
struct TapToTrackSetupView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\CardMapping.displayCardName)]) private var mappings: [CardMapping]
    @Query(filter: #Predicate<SubAccount> { !$0.isArchived }) private var accounts: [SubAccount]
    @State private var addingCard = false
    @State private var testResult: String?
    @State private var testTxID: UUID?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("How it works", systemImage: "wave.3.right.circle.fill").font(.headline)
                    Text("When you pay in-store with Apple Pay, an iOS automation runs a Qazyna action in the background and logs the expense automatically — no need to open the app.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section {
                step(1, "Open **Shortcuts** → **Automation** tab → **＋** → **Create Personal Automation**.")
                step(2, "Choose **Transaction** (shown as **Wallet** on iOS 26).")
                step(3, "Set **When I use** → the card you pay with (or **Any Card**), then tap **Next**.")
                step(4, "**Add Action**, search **Qazyna**, and choose **Log Apple Pay Expense**.")
                step(5, "In that action, tap **Amount** and insert the transaction's **Amount** variable; tap **Merchant** and insert **Merchant**. Tap **Next**.")
                step(6, "Choose **Run Immediately** (not *Ask Before Running*), then **Done**.")
            } header: {
                Text("Set up the automation (once per device)")
            } footer: {
                Text("The two things people miss: (1) **Run Immediately** must be on — if it's set to *Ask Before Running*, iOS only sends a prompt and nothing logs on its own; (2) the **Amount** (and Merchant) variable must actually be inserted into the action's fields.")
            }

            Section {
                ForEach(mappings) { m in
                    HStack {
                        Image(systemName: "creditcard.fill").foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(m.displayCardName).font(.subheadline.weight(.medium))
                            Text("→ \(accountName(m.accountID)) · \(m.defaultCurrencyCode)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { context.delete(m); try? context.save() } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Button { addingCard = true } label: { Label("Map a card", systemImage: "plus") }
                    .disabled(accounts.isEmpty)
            } header: {
                Text("Card → account mapping")
            } footer: {
                Text("Use the exact Wallet card name (as shown in the automation). Taps from an unmapped card go to your first card account and are flagged for review.")
            }

            Section {
                Button { runTest() } label: { Label("Log a test transaction", systemImage: "checkmark.circle") }
                    .disabled(accounts.isEmpty)
                if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary) }
                if testTxID != nil {
                    Button(role: .destructive) { undoTest() } label: {
                        Label("Undo test transaction", systemImage: "arrow.uturn.backward")
                    }
                }
            } header: {
                Text("Test the connection")
            } footer: {
                Text("Adds a real 1 000 ₸ transaction through the exact path a tap uses, so you can see it appear in History and your balances update. Tap Undo to remove it. If this works, the app side is fine and any problem is in the Shortcuts automation itself.")
            }

            Section {
                tip("Your flow — double-click, authenticate, hold your card to the terminal — is exactly what this tracks. It fires when that in-store payment **completes**, so test it on a real purchase (opening Wallet alone won't trigger it).")
                tip("If it still doesn't fire, it's almost always **Run Immediately** being off, or the card in the trigger not matching the card you paid with — recheck steps 3 and 6 above.")
                tip("It works only for **in-store contactless taps on this iPhone** — not Apple Watch, online/in-app, or QR / Kaspi / Alaqan payments.")
                tip("In Shortcuts, make sure the automation's card filter matches the card you tapped (or pick **Any Card**), Transaction Type is **Payment**, **Run Immediately** is on, and **Notify When Run** is off.")
                tip("On iOS 26 the trigger lives under **Wallet**, not Transaction.")
                tip("Some Kazakhstani cards don't expose transactions to Shortcuts at all. Test with your specific card; use manual entry or receipt scan as a fallback.")
            } header: {
                Text("If it doesn't log")
            }
        }
        .navigationTitle("Tap to Track")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingCard) { CardMappingEditor(accounts: accounts) }
    }

    private func tip(_ markdown: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wrench.and.screwdriver").font(.caption).foregroundStyle(.orange).frame(width: 22)
            Text(.init(markdown)).font(.caption)
        }
    }

    private func runTest() {
        do {
            let r = try TapLogger.log(rawAmount: "1000", merchant: "Test capture",
                                      card: mappings.first?.displayCardName, currency: nil, in: context)
            testTxID = r.transaction.id
            let acct = accounts.first { $0.id == r.transaction.accountID }
            testResult = "✓ Logged \(CurrencyFormatter.string(r.transaction.amountOriginal, currencyCode: r.transaction.currencyCode)) to \(acct.map { "\($0.bank?.name ?? "") \($0.name)" } ?? "your account") — it's now in History and your balance updated."
            Haptics.success()
        } catch {
            testResult = "Couldn't log a test — add an account first (Accounts tab)."
            Haptics.error()
        }
    }

    private func undoTest() {
        guard let id = testTxID else { return }
        var d = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        if let tx = try? context.fetch(d).first { try? Ledger.delete(tx, in: context) }
        testTxID = nil
        testResult = "Test transaction removed."
        Haptics.tap()
    }

    private func step(_ n: Int, _ markdown: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(.tint))
            Text(.init(markdown)).font(.subheadline)
        }
    }

    private func accountName(_ id: UUID) -> String {
        accounts.first { $0.id == id }.map { "\($0.bank?.name ?? "") \($0.name)" } ?? "—"
    }
}

struct CardMappingEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let accounts: [SubAccount]

    @State private var cardName = ""
    @State private var accountID: UUID?
    @State private var currency = Money.baseCurrency

    var body: some View {
        NavigationStack {
            Form {
                Section("Wallet card name") {
                    TextField("e.g. Kaspi Gold", text: $cardName)
                }
                Section("Logs to") {
                    Picker("Account", selection: $accountID) {
                        ForEach(accounts) { a in Text("\(a.bank?.name ?? "") · \(a.name)").tag(Optional(a.id)) }
                    }
                    CurrencyPicker(selection: $currency)
                }
            }
            .navigationTitle("Map Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(cardName.isEmpty || accountID == nil)
                }
            }
            .onAppear {
                accountID = accounts.first?.id
                currency = accounts.first?.currencyCode ?? Money.baseCurrency
            }
            .onChange(of: accountID) { _, id in
                if let acct = accounts.first(where: { $0.id == id }) { currency = acct.currencyCode }
            }
        }
    }

    private func save() {
        guard let accountID else { return }
        let key = CardMapping.normalize(cardName)
        // Upsert by card key.
        var d = FetchDescriptor<CardMapping>(predicate: #Predicate { $0.cardKey == key }); d.fetchLimit = 1
        if let existing = try? context.fetch(d).first {
            existing.displayCardName = cardName; existing.accountID = accountID; existing.defaultCurrencyCode = currency
        } else {
            context.insert(CardMapping(cardKey: key, displayCardName: cardName, accountID: accountID, defaultCurrencyCode: currency))
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
