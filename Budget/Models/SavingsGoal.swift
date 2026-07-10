import Foundation
import SwiftData

/// A savings goal (in KZT) linked to a sub-account (e.g. a deposit). Progress tracks that
/// account's balance toward `targetKZT`; a projected completion date is derived from the
/// recent contribution pace.
@Model
final class SavingsGoal {
    @Attribute(.unique) var id: UUID
    var name: String
    var targetKZT: Decimal
    /// The sub-account whose balance funds the goal (nil = manual tracking).
    var linkedAccountID: UUID?
    /// Amount to count as already saved if not tied to an account balance.
    var manualSavedKZT: Decimal
    var targetDate: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        targetKZT: Decimal,
        linkedAccountID: UUID? = nil,
        manualSavedKZT: Decimal = 0,
        targetDate: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.targetKZT = targetKZT
        self.linkedAccountID = linkedAccountID
        self.manualSavedKZT = manualSavedKZT
        self.targetDate = targetDate
        self.createdAt = createdAt
    }
}
