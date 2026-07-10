import Foundation
import SwiftData

/// A single expense or income entry. Stores the original amount + currency, the KZT
/// conversion rate snapshotted at entry time, and a precomputed `amountKZT` so all KZT
/// totals are `Σ amountKZT` — stable and auditable regardless of later FX moves.
///
/// Foreign keys and date buckets are denormalized as indexed scalars (`accountID`,
/// `categoryID`, `dateKey`, `monthKey`) so every analytics `#Predicate` is a flat
/// primitive comparison.
@Model
final class TransactionRecord {
    #Index<TransactionRecord>([\.dateKey], [\.monthKey], [\.accountID], [\.dedupKey])

    @Attribute(.unique) var id: UUID
    /// Deterministic key making capture idempotent (a re-fired Shortcut / re-run import
    /// cannot create a duplicate). SwiftData upserts in place on a `.unique` conflict.
    @Attribute(.unique) var dedupKey: String

    var kindRaw: String
    var amountOriginal: Decimal        // in the account's currency
    var currencyCode: String           // == account.currencyCode (invariant)
    var fxRateToKZT: Decimal           // KZT per 1 unit of currencyCode, snapshot at entry
    var amountKZT: Decimal             // precomputed = amountOriginal * fxRateToKZT (rounded)

    var date: Date
    var dateKey: Int                   // yyyymmdd
    var monthKey: Int                  // yyyymm

    var accountID: UUID                // denormalized FK
    var categoryID: String             // denormalized FK (category slug)
    var merchant: String?
    var note: String?
    var sourceRaw: String              // EntrySource raw
    /// Needs user review (e.g. Tap-to-Track with guessed currency/category).
    var needsReview: Bool
    /// Whether this row's contribution has been applied to the rollups (reconcile guard).
    var rolledUp: Bool
    var createdAt: Date

    var account: SubAccount?

    init(
        id: UUID = UUID(),
        dedupKey: String,
        kind: TransactionKind,
        amountOriginal: Decimal,
        currencyCode: String,
        fxRateToKZT: Decimal,
        date: Date,
        accountID: UUID,
        categoryID: String,
        merchant: String? = nil,
        note: String? = nil,
        source: EntrySource = .manual,
        needsReview: Bool = false,
        createdAt: Date = .now,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.dedupKey = dedupKey
        self.kindRaw = kind.rawValue
        self.amountOriginal = amountOriginal
        self.currencyCode = currencyCode
        self.fxRateToKZT = fxRateToKZT
        self.amountKZT = Money.roundedKZT(amountOriginal * fxRateToKZT)
        self.date = date
        self.dateKey = DateKeys.dayKey(date, calendar: calendar)
        self.monthKey = DateKeys.monthKey(date, calendar: calendar)
        self.accountID = accountID
        self.categoryID = categoryID
        self.merchant = merchant
        self.note = note
        self.sourceRaw = source.rawValue
        self.needsReview = needsReview
        self.rolledUp = false
        self.createdAt = createdAt
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// Signed KZT delta this row applies to its account balance and to spending rollups.
    var signedAmountKZT: Decimal { amountKZT * Decimal(kind.balanceSign) }
    var signedAmountOriginal: Decimal { amountOriginal * Decimal(kind.balanceSign) }
}
