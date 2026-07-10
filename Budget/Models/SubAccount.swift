import Foundation
import SwiftData

/// A location of money inside a bank (card / deposit / savings / cash / asset / loan).
/// This is the **balance owner**: expenses, income, transfers and manual adjustments all
/// move `cachedBalance`, which is a denormalized running total always rebuildable from the ledger.
@Model
final class SubAccount {
    @Attribute(.unique) var id: UUID
    var name: String
    /// `AccountType` raw value (stored as String for predicate safety).
    var typeRaw: String
    /// The account's native ISO currency; every transaction on it shares this currency.
    var currencyCode: String
    /// Anchor balance at `openingBalanceDate`, in the account's currency.
    var openingBalance: Decimal
    var openingBalanceDate: Date
    /// Denormalized running balance = openingBalance + Σ ledger deltas (account currency).
    var cachedBalance: Decimal
    var includeInNetWorth: Bool
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: Date

    var bank: Bank?

    @Relationship(deleteRule: .cascade, inverse: \TransactionRecord.account)
    var transactions: [TransactionRecord] = []

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        currencyCode: String = Money.baseCurrency,
        openingBalance: Decimal = 0,
        openingBalanceDate: Date = .now,
        includeInNetWorth: Bool = true,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.currencyCode = currencyCode
        self.openingBalance = openingBalance
        self.openingBalanceDate = openingBalanceDate
        self.cachedBalance = openingBalance
        self.includeInNetWorth = includeInNetWorth
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .cash }
        set { typeRaw = newValue.rawValue }
    }

    /// Signed contribution of this account to net worth in its own currency
    /// (liabilities subtract).
    var signedBalance: Decimal {
        type.isLiability ? -cachedBalance : cachedBalance
    }
}
