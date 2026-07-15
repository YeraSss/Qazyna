import Foundation
import SwiftData

/// First-launch seeding of the default **category taxonomy** only. No sample accounts,
/// transactions, budgets, or goals are ever created — the user starts with a clean slate and
/// is guided by the onboarding walkthrough + empty states. The Kazakhstani banks are offered
/// as one-tap presets in the Add Bank flow (see `SeedData.bankPresets`) rather than
/// pre-created rows.
enum SeedData {

    // MARK: Bank presets (offered in the Add Bank UI — not seeded into the store)

    struct BankPreset: Identifiable {
        let id, name, domain, color: String
    }

    static let bankPresets: [BankPreset] = [
        BankPreset(id: "kaspi.kz",          name: "Kaspi",       domain: "kaspi.kz",          color: "#F14635"),
        BankPreset(id: "bankffin.kz",       name: "Freedom",     domain: "bankffin.kz",       color: "#51AF3D"),
        BankPreset(id: "home.kz",           name: "Home Credit", domain: "home.kz",           color: "#E51937"),
        BankPreset(id: "alataucitybank.kz", name: "Alatau City", domain: "alataucitybank.kz", color: "#F2B705"),
        BankPreset(id: "forte.kz",          name: "ForteBank",   domain: "forte.kz",          color: "#00A9A5"),
        BankPreset(id: "halyk.kz",          name: "Halyk",       domain: "halykbank.kz",      color: "#00A94F"),
        BankPreset(id: "jusan.kz",          name: "Jusan",       domain: "jusan.kz",          color: "#111111")
    ]

    // MARK: Default categories (the taxonomy; expected reference data)

    struct CategorySeed { let id, name, emoji, color: String; let kind: TransactionKind }

    static let categories: [CategorySeed] = [
        // Expenses
        CategorySeed(id: "food",          name: "Food & Dining",   emoji: "🍽️", color: "#FF6B4A", kind: .expense),
        CategorySeed(id: "groceries",     name: "Groceries",       emoji: "🛒", color: "#4CAF50", kind: .expense),
        CategorySeed(id: "transport",     name: "Transport",       emoji: "🚗", color: "#3F8CFF", kind: .expense),
        CategorySeed(id: "shopping",      name: "Shopping",        emoji: "🛍️", color: "#E040FB", kind: .expense),
        CategorySeed(id: "bills",         name: "Bills & Utilities", emoji: "🧾", color: "#FFB300", kind: .expense),
        CategorySeed(id: "rent",          name: "Rent & Housing",  emoji: "🏠", color: "#8D6E63", kind: .expense),
        CategorySeed(id: "entertainment", name: "Entertainment",   emoji: "🎬", color: "#7C4DFF", kind: .expense),
        CategorySeed(id: "health",        name: "Health",          emoji: "💊", color: "#26C6DA", kind: .expense),
        CategorySeed(id: "subscriptions", name: "Subscriptions",   emoji: "🔁", color: "#EC407A", kind: .expense),
        CategorySeed(id: "travel",        name: "Travel",          emoji: "✈️", color: "#29B6F6", kind: .expense),
        CategorySeed(id: "education",     name: "Education",        emoji: "📚", color: "#5C6BC0", kind: .expense),
        CategorySeed(id: "other",         name: "Other",           emoji: "📦", color: "#90A4AE", kind: .expense),
        // Income
        CategorySeed(id: "salary",        name: "Salary",          emoji: "💰", color: "#2E9E5B", kind: .income),
        CategorySeed(id: "freelance",     name: "Freelance",       emoji: "🧑‍💻", color: "#00897B", kind: .income),
        CategorySeed(id: "gift",          name: "Gift",            emoji: "🎁", color: "#AB47BC", kind: .income),
        CategorySeed(id: "income_other",  name: "Other Income",    emoji: "➕", color: "#66BB6A", kind: .income)
    ]

    /// Backfill logo domains for banks created before domains were captured (or added via a
    /// preset that didn't store one): match an empty-domain bank to a preset by name. Idempotent.
    static func backfillBankDomains(_ context: ModelContext) {
        guard let banks = try? context.fetch(FetchDescriptor<Bank>()) else { return }
        var changed = false
        for bank in banks where bank.domain.trimmingCharacters(in: .whitespaces).isEmpty {
            if let preset = bankPresets.first(where: { $0.name.caseInsensitiveCompare(bank.name) == .orderedSame }) {
                bank.domain = preset.domain
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// Seed default categories if none exist. Idempotent; safe on every launch.
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        guard count == 0 else { return }
        for (index, seed) in categories.enumerated() {
            context.insert(Category(id: seed.id, name: seed.name, emoji: seed.emoji,
                                    colorHex: seed.color, kind: seed.kind, sortOrder: index))
        }
        try? context.save()
    }
}
