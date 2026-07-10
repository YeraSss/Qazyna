import SwiftUI
import SwiftData
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fx: FXRateService
    @EnvironmentObject private var appLock: AppLock
    @State private var notificationsAuthorized = false
    @State private var showSetPIN = false
    @State private var showWalkthrough = false
    @State private var showRestore = false
    @State private var csvDocument: TextDocument?
    @State private var jsonDocument: DataDocument?
    @State private var exportingCSV = false
    @State private var exportingJSON = false
    @State private var restoreMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Setup") {
                    Button { showWalkthrough = true } label: {
                        Label("How Qazyna works", systemImage: "sparkles")
                    }
                    NavigationLink { TapToTrackSetupView() } label: {
                        Label("Tap to Track", systemImage: "wave.3.right.circle")
                    }
                    NavigationLink { CategoryManagementView() } label: {
                        Label("Categories", systemImage: "tag")
                    }
                }

                Section {
                    HStack {
                        Label("Notifications", systemImage: "bell.badge")
                        Spacer()
                        Text(notificationsAuthorized ? "On" : "Off").foregroundStyle(.secondary)
                    }
                    if !notificationsAuthorized {
                        Button("Enable notifications") {
                            Task { notificationsAuthorized = await NotificationService.requestAuthorization() }
                        }
                    }
                } footer: {
                    Text("Used for budget-limit warnings and recurring reminders. Local only — nothing leaves your device.")
                }

                Section {
                    HStack {
                        Label("Exchange rates", systemImage: "dollarsign.arrow.circlepath")
                        Spacer()
                        if fx.isRefreshing { ProgressView() }
                        else { Text(fx.isStale ? "Stale" : "Up to date").foregroundStyle(fx.isStale ? .orange : .secondary) }
                    }
                    Text(fx.ratesAsOfText).font(.caption).foregroundStyle(.secondary)
                    Button("Refresh rates now") { Task { await fx.refresh() } }
                        .disabled(fx.isRefreshing)
                } header: {
                    Text("Currency")
                } footer: {
                    Text("Rates are cached on-device for offline use. Base currency is KZT (₸). Source: fawazahmed0 Currency API (community, CC0). Not an official National Bank of Kazakhstan valuation.")
                }

                Section {
                    NavigationLink { ImportView() } label: { Label("Import CSV", systemImage: "square.and.arrow.down") }
                    Button { exportCSV() } label: { Label("Export transactions (CSV)", systemImage: "tablecells") }
                    Button { exportJSON() } label: { Label("Export backup (JSON)", systemImage: "square.and.arrow.up") }
                    Button { showRestore = true } label: { Label("Restore backup (JSON)", systemImage: "arrow.uturn.backward") }
                    if let restoreMessage { Text(restoreMessage).font(.caption).foregroundStyle(.secondary) }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export a spreadsheet-friendly CSV or a full JSON backup. Restore replaces all current data with a backup file.")
                }

                Section {
                    Toggle(isOn: $appLock.isEnabled) {
                        Label("Require \(appLock.biometryLabel)", systemImage: "lock.shield")
                    }
                    if appLock.isEnabled {
                        Button { showSetPIN = true } label: {
                            Label(appLock.hasPIN() ? "Change PIN" : "Set backup PIN", systemImage: "number.square")
                        }
                        if appLock.hasPIN() {
                            Button(role: .destructive) { appLock.clearPIN() } label: { Label("Remove PIN", systemImage: "xmark.square") }
                        }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Lock the app with Face ID / Touch ID / passcode on launch and when it returns from the background.")
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    Text("Offline-first. All data stays on your device.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task { notificationsAuthorized = await NotificationService.authorizationStatus() == .authorized }
            .fileExporter(isPresented: $exportingCSV, document: csvDocument, contentType: .commaSeparatedText, defaultFilename: "budget-transactions") { _ in }
            .fileExporter(isPresented: $exportingJSON, document: jsonDocument, contentType: .json, defaultFilename: "budget-backup") { _ in }
            .fileImporter(isPresented: $showRestore, allowedContentTypes: [.json]) { result in restore(result) }
            .sheet(isPresented: $showSetPIN) { SetPINView(appLock: appLock) }
            .sheet(isPresented: $showWalkthrough) { OnboardingView { showWalkthrough = false } }
        }
    }

    private func exportCSV() {
        csvDocument = TextDocument(text: ImportExportService.transactionsCSV(in: context))
        exportingCSV = true
    }
    private func exportJSON() {
        if let data = ImportExportService.exportBackup(in: context) {
            jsonDocument = DataDocument(data: data); exportingJSON = true
        }
    }
    private func restore(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            try ImportExportService.restoreBackup(data, in: context)
            restoreMessage = "Backup restored."
            Haptics.success()
        } catch {
            restoreMessage = "Restore failed: \(error.localizedDescription)"
            Haptics.error()
        }
    }
}

/// Sets or changes the backup PIN.
struct SetPINView: View {
    @ObservedObject var appLock: AppLock
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var confirm = ""
    var body: some View {
        NavigationStack {
            Form {
                SecureField("PIN (4+ digits)", text: $pin).keyboardType(.numberPad)
                SecureField("Confirm PIN", text: $confirm).keyboardType(.numberPad)
            }
            .navigationTitle("Backup PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { appLock.setPIN(pin); Haptics.success(); dismiss() }
                        .disabled(pin.count < 4 || pin != confirm)
                }
            }
        }
    }
}

/// Minimal FileDocument wrappers for the exporters.
struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
struct DataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
