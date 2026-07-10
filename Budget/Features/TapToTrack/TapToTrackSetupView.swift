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

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("How it works", systemImage: "wave.3.right.circle.fill").font(.headline)
                    Text("When you pay in-store with Apple Pay, an iOS automation runs a Qazyna action in the background and logs the expense automatically — no need to open the app.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section("Set up the automation (once per device)") {
                step(1, "Open the **Shortcuts** app → **Automation** tab → **＋ New Automation**.")
                step(2, "Choose **Transaction** (called **Wallet** on iOS 26) → **When I use a card**.")
                step(3, "Pick the card(s) you want tracked, and set **Transaction Type: Payment**.")
                step(4, "Turn on **Run Immediately** and turn **off** *Notify When Run* for silent logging.")
                step(5, "Add action **Log Apple Pay Expense** (from Qazyna).")
                step(6, "Map **Shortcut Input → Amount** to *Amount*, and **Merchant** to *Merchant*.")
                step(7, "Save. Now every tap-to-pay logs to Qazyna automatically.")
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
                Label {
                    Text("Captures **in-store iPhone Apple Pay taps only** — not Apple Watch, online, or QR/Kaspi/Alaqan payments. Keep using manual entry for those. Currency isn't passed by the automation, so foreign taps default to the card's currency and are flagged for review.")
                        .font(.caption)
                } icon: { Image(systemName: "info.circle").foregroundStyle(.orange) }
            } header: {
                Text("Good to know")
            }
        }
        .navigationTitle("Tap to Track")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingCard) { CardMappingEditor(accounts: accounts) }
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
