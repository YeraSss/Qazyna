import Foundation
import SwiftData

/// A bank (or institution) grouping one or more sub-accounts. Shown on the Accounts
/// screen with a single total that expands to its sub-accounts.
@Model
final class Bank {
    /// Deterministic id — the domain slug for known banks (e.g. "kaspi.kz"), a UUID string for custom ones.
    @Attribute(.unique) var id: String
    var name: String
    /// Domain used for logo resolution (Phase 6 logo API); also anchors identity for seeded banks.
    var domain: String
    /// Brand color hex for the monogram tile fallback (always present).
    var brandColorHex: String
    /// Filename of a locally cached / user-imported logo image, nil until one exists.
    var logoCacheKey: String?
    var sortOrder: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SubAccount.bank)
    var subAccounts: [SubAccount] = []

    init(
        id: String,
        name: String,
        domain: String,
        brandColorHex: String,
        logoCacheKey: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.brandColorHex = brandColorHex
        self.logoCacheKey = logoCacheKey
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// Two-letter monogram used on the fallback tile.
    var monogram: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        let text = String(letters).uppercased()
        return text.isEmpty ? String(name.prefix(1)).uppercased() : text
    }
}
