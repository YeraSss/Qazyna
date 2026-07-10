import Foundation

/// The common input for creating or editing a transaction. Produced by manual quick-add,
/// the NL parser, receipt/statement OCR, CSV import, and the Tap-to-Track intent — so every
/// capture path funnels through the same `Ledger` write logic.
///
/// `fxRateToKZT` is supplied by the caller (from `FXRateService`) so `Ledger` stays FX-agnostic.
struct TransactionDraft {
    var id: UUID?              // nil ⇒ new
    var dedupKey: String?      // nil ⇒ generated
    var kind: TransactionKind
    var amountOriginal: Decimal
    var currencyCode: String
    var fxRateToKZT: Decimal
    var date: Date
    var accountID: UUID
    var categoryID: String
    var merchant: String?
    var note: String?
    var source: EntrySource
    var needsReview: Bool

    init(
        id: UUID? = nil,
        dedupKey: String? = nil,
        kind: TransactionKind,
        amountOriginal: Decimal,
        currencyCode: String,
        fxRateToKZT: Decimal,
        date: Date = .now,
        accountID: UUID,
        categoryID: String,
        merchant: String? = nil,
        note: String? = nil,
        source: EntrySource = .manual,
        needsReview: Bool = false
    ) {
        self.id = id
        self.dedupKey = dedupKey
        self.kind = kind
        self.amountOriginal = amountOriginal
        self.currencyCode = currencyCode
        self.fxRateToKZT = fxRateToKZT
        self.date = date
        self.accountID = accountID
        self.categoryID = categoryID
        self.merchant = merchant
        self.note = note
        self.source = source
        self.needsReview = needsReview
    }
}

/// Input for a transfer between two sub-accounts.
struct TransferDraft {
    var fromAccountID: UUID
    var toAccountID: UUID
    var fromAmount: Decimal
    var fromCurrencyCode: String
    var toAmount: Decimal
    var toCurrencyCode: String
    var date: Date = .now
    var note: String?
}
