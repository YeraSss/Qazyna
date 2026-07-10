import Foundation
import SwiftData

/// An explicit ledger entry recording a manual balance correction. We *never* overwrite
/// `cachedBalance` directly — instead we write the delta needed to reach the target so the
/// invariant `cachedBalance == openingBalance + Σ(transactions) + Σ(adjustments) ± transfers`
/// always holds and the balance stays fully rebuildable.
@Model
final class BalanceAdjustment {
    @Attribute(.unique) var id: UUID
    var accountID: UUID
    var delta: Decimal          // in account currency (target - previous)
    var reason: String?
    var date: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        accountID: UUID,
        delta: Decimal,
        reason: String? = nil,
        date: Date = .now,
        createdAt: Date = .now
    ) {
        self.id = id
        self.accountID = accountID
        self.delta = delta
        self.reason = reason
        self.date = date
        self.createdAt = createdAt
    }
}
