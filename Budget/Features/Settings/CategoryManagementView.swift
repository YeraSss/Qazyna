import SwiftUI
import SwiftData

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Category.sortOrder)]) private var categories: [Category]
    @State private var editing: Category?
    @State private var adding = false

    private var expense: [Category] { categories.filter { $0.kind == .expense } }
    private var income: [Category] { categories.filter { $0.kind == .income } }

    var body: some View {
        List {
            section("Expense", income: false, items: expense)
            section("Income", income: true, items: income)
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) { CategoryEditorView(category: nil) }
        .sheet(item: $editing) { CategoryEditorView(category: $0) }
    }

    private func section(_ title: String, income: Bool, items: [Category]) -> some View {
        Section(title) {
            ForEach(items) { cat in
                HStack {
                    Text(cat.emoji)
                    Text(cat.name)
                    if cat.isArchived { Text("Archived").font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                    Circle().fill(Color(hex: cat.colorHex)).frame(width: 14, height: 14)
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = cat }
                .swipeActions {
                    Button(role: .destructive) { delete(cat) } label: { Label("Delete", systemImage: "trash") }
                    Button { cat.isArchived.toggle(); try? context.save() } label: {
                        Label(cat.isArchived ? "Restore" : "Archive", systemImage: "archivebox")
                    }.tint(.orange)
                }
            }
        }
    }

    private func delete(_ cat: Category) {
        context.delete(cat)
        try? context.save()
    }
}

struct CategoryEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allCategories: [Category]

    let category: Category?
    @State private var name = ""
    @State private var emoji = "🏷️"
    @State private var color: Color = .blue
    @State private var kind: TransactionKind = .expense

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Emoji", text: $emoji)
                        .onChange(of: emoji) { _, v in emoji = String(v.prefix(2)) }
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                    Picker("Type", selection: $kind) {
                        Text("Expense").tag(TransactionKind.expense)
                        Text("Income").tag(TransactionKind.income)
                    }.pickerStyle(.segmented)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let category {
                    name = category.name; emoji = category.emoji
                    color = Color(hex: category.colorHex); kind = category.kind
                }
            }
        }
    }

    private func save() {
        if let category {
            category.name = name; category.emoji = emoji
            category.colorHex = color.hexString(); category.kind = kind
        } else {
            let slug = name.lowercased().replacingOccurrences(of: " ", with: "_") + "_" + String(UUID().uuidString.prefix(4))
            let new = Category(id: slug, name: name, emoji: emoji, colorHex: color.hexString(),
                               kind: kind, sortOrder: (allCategories.map(\.sortOrder).max() ?? 0) + 1)
            context.insert(new)
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
