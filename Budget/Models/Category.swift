import Foundation
import SwiftData

/// A spending or income category. Identified by a stable slug so imports / merchant
/// mappings can reference it deterministically.
@Model
final class Category {
    @Attribute(.unique) var id: String   // slug, e.g. "food", "salary"
    var name: String
    var emoji: String
    var colorHex: String
    /// `TransactionKind` raw value — a category is either expense-side or income-side.
    var kindRaw: String
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date

    init(
        id: String,
        name: String,
        emoji: String,
        colorHex: String,
        kind: TransactionKind = .expense,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }
}
