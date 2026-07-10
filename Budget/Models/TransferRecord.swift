import Foundation
import SwiftData

/// A movement of money between two sub-accounts (e.g. card → deposit). It touches two
/// balances but is **not** a `TransactionKind`, so it never appears in spending analytics
/// and writes no spending rollup. Cross-currency transfers are allowed (amounts per side).
@Model
final class TransferRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var dedupKey: String

    var fromAccountID: UUID
    var toAccountID: UUID
    var fromAmount: Decimal       // in fromAccount currency
    var fromCurrencyCode: String
    var toAmount: Decimal         // in toAccount currency
    var toCurrencyCode: String
    var date: Date
    var note: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        dedupKey: String = UUID().uuidString,
        fromAccountID: UUID,
        toAccountID: UUID,
        fromAmount: Decimal,
        fromCurrencyCode: String,
        toAmount: Decimal,
        toCurrencyCode: String,
        date: Date = .now,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.dedupKey = dedupKey
        self.fromAccountID = fromAccountID
        self.toAccountID = toAccountID
        self.fromAmount = fromAmount
        self.fromCurrencyCode = fromCurrencyCode
        self.toAmount = toAmount
        self.toCurrencyCode = toCurrencyCode
        self.date = date
        self.note = note
        self.createdAt = createdAt
    }
}
