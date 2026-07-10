import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Import transactions from a bank CSV: pick a file, map columns, choose the target account.
struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fx: FXRateService
    @Query(filter: #Predicate<SubAccount> { !$0.isArchived }) private var accounts: [SubAccount]

    @State private var showFileImporter = false
    @State private var header: [String] = []
    @State private var rows: [[String]] = []
    @State private var mapping = ImportExportService.CSVMapping()
    @State private var accountID: UUID?
    @State private var importedCount: Int?
    @State private var error: String?

    private var account: SubAccount? { accounts.first { $0.id == accountID } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showFileImporter = true } label: { Label("Choose CSV file", systemImage: "doc") }
                } footer: {
                    Text("Most banks let you export statements as CSV. Pick the file, then map its columns below.")
                }

                if let error { Text(error).foregroundStyle(.red) }

                if !header.isEmpty {
                    Section("Map columns") {
                        columnPicker("Date", $mapping.date)
                        columnPicker("Amount", $mapping.amount)
                        columnPicker("Merchant", $mapping.merchant)
                        columnPicker("Category", $mapping.category)
                        columnPicker("Type (expense/income)", $mapping.kind)
                        columnPicker("Note", $mapping.note)
                    }
                    Section("Import into") {
                        Picker("Account", selection: $accountID) {
                            ForEach(accounts) { a in Text("\(a.bank?.name ?? "") · \(a.name)").tag(Optional(a.id)) }
                        }
                    }
                    Section {
                        Button {
                            doImport()
                        } label: {
                            Text("Import \(rows.count) row\(rows.count == 1 ? "" : "s")")
                        }
                        .disabled(mapping.amount == nil || accountID == nil)
                    }
                }

                if let importedCount {
                    Section { Label("Imported \(importedCount) transactions", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                handleFile(result)
            }
            .onAppear { accountID = accounts.first?.id }
        }
    }

    private func columnPicker(_ label: String, _ binding: Binding<Int?>) -> some View {
        Picker(label, selection: binding) {
            Text("None").tag(Int?.none)
            ForEach(Array(header.enumerated()), id: \.offset) { i, name in
                Text(name.isEmpty ? "Column \(i + 1)" : name).tag(Int?.some(i))
            }
        }
    }

    private func handleFile(_ result: Result<URL, Error>) {
        error = nil; importedCount = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = ImportExportService.parseCSV(text)
            guard let head = parsed.first, parsed.count > 1 else { error = "The file looks empty."; return }
            header = head
            rows = Array(parsed.dropFirst())
            mapping = guessMapping(head)
        } catch {
            self.error = "Couldn't read the file: \(error.localizedDescription)"
        }
    }

    private func guessMapping(_ header: [String]) -> ImportExportService.CSVMapping {
        var m = ImportExportService.CSVMapping()
        for (i, name) in header.enumerated() {
            let n = name.lowercased()
            if m.date == nil, n.contains("date") { m.date = i }
            if m.amount == nil, n.contains("amount") || n.contains("sum") || n.contains("value") { m.amount = i }
            if m.merchant == nil, n.contains("merchant") || n.contains("description") || n.contains("payee") || n.contains("name") { m.merchant = i }
            if m.category == nil, n.contains("category") { m.category = i }
            if m.kind == nil, n.contains("type") || n.contains("kind") { m.kind = i }
            if m.note == nil, n.contains("note") || n.contains("memo") { m.note = i }
        }
        return m
    }

    private func doImport() {
        guard let account else { return }
        let rate = fx.rateToKZT(account.currencyCode)
        let count = ImportExportService.importCSV(rows: rows, mapping: mapping, into: account, fxRate: rate, in: context)
        importedCount = count
        BudgetAlerts.evaluate(in: context)
        Haptics.success()
    }
}
