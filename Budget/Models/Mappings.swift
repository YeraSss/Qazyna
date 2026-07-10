import Foundation
import SwiftData

/// Learned merchant → category association. Created/updated when the user corrects the
/// category of a `needsReview` transaction, so future Tap-to-Track / NL entries auto-categorize.
@Model
final class MerchantMapping {
    /// Normalized merchant string (lowercased, trimmed) — unique lookup key.
    @Attribute(.unique) var merchantKey: String
    var displayMerchant: String
    var categoryID: String
    var hitCount: Int
    var updatedAt: Date

    init(
        merchantKey: String,
        displayMerchant: String,
        categoryID: String,
        hitCount: Int = 1,
        updatedAt: Date = .now
    ) {
        self.merchantKey = merchantKey
        self.displayMerchant = displayMerchant
        self.categoryID = categoryID
        self.hitCount = hitCount
        self.updatedAt = updatedAt
    }

    static func normalize(_ merchant: String) -> String {
        merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Maps an Apple Wallet card name (as passed by the Shortcuts automation) to a sub-account
/// and a default currency, so a tap logs against the correct account.
@Model
final class CardMapping {
    /// Normalized Wallet card name — unique lookup key.
    @Attribute(.unique) var cardKey: String
    var displayCardName: String
    var accountID: UUID
    /// Currency to assume when the automation doesn't pass one (fallback to KZT if nil).
    var defaultCurrencyCode: String
    var createdAt: Date

    init(
        cardKey: String,
        displayCardName: String,
        accountID: UUID,
        defaultCurrencyCode: String = Money.baseCurrency,
        createdAt: Date = .now
    ) {
        self.cardKey = cardKey
        self.displayCardName = displayCardName
        self.accountID = accountID
        self.defaultCurrencyCode = defaultCurrencyCode
        self.createdAt = createdAt
    }

    static func normalize(_ cardName: String) -> String {
        cardName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
