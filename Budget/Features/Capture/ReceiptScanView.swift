import SwiftUI
import SwiftData
import PhotosUI

/// Pick a receipt photo, OCR it on-device (Vision), and hand a pre-filled draft to quick-add
/// for the user to confirm. Works with photos on the Simulator; on a device you can also use
/// the camera via the Photos picker. OCR is always a draft — never auto-committed.
struct ReceiptScanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var processing = false
    @State private var lines: [String] = []
    @State private var prefill: ParsedEntry?
    @State private var showConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ContentUnavailableView("Scan a receipt", systemImage: "doc.text.viewfinder",
                                               description: Text("Pick a photo of a receipt. We'll read the total and merchant on-device."))
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(image == nil ? "Choose photo" : "Choose another", systemImage: "photo")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    if processing { ProgressView("Reading receipt…") }

                    if !lines.isEmpty {
                        DisclosureGroup("Recognized text (\(lines.count) lines)") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                                    Text(l).font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding().background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                    }
                }
                .padding()
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: pickerItem) { _, item in Task { await handle(item) } }
            .sheet(isPresented: $showConfirm, onDismiss: { dismiss() }) {
                QuickAddView(prefill: prefill)
            }
        }
    }

    private func handle(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        processing = true
        defer { processing = false }
        guard let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) else { return }
        image = ui
        let (entry, recognized) = await ReceiptOCR.parseReceipt(from: ui, in: context)
        lines = recognized
        prefill = entry
        if entry.amount != nil { showConfirm = true }
    }
}
