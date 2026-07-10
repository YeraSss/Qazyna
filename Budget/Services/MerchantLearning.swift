import Foundation
import SwiftData

/// Local merchant → category learning. When the user assigns/corrects a category for a
/// transaction that has a merchant, we remember it so future Tap-to-Track / NL entries from
/// the same merchant auto-categorize. Everything stays on-device.
enum MerchantLearning {

    /// Look up a learned category for a merchant string, if any.
    static func category(for merchant: String, in context: ModelContext) -> String? {
        let key = MerchantMapping.normalize(merchant)
        guard !key.isEmpty else { return nil }
        var d = FetchDescriptor<MerchantMapping>(predicate: #Predicate { $0.merchantKey == key })
        d.fetchLimit = 1
        return try? context.fetch(d).first?.categoryID
    }

    /// Record (or reinforce) a merchant → category association.
    static func learn(merchant: String, categoryID: String, in context: ModelContext) {
        let key = MerchantMapping.normalize(merchant)
        guard !key.isEmpty else { return }
        var d = FetchDescriptor<MerchantMapping>(predicate: #Predicate { $0.merchantKey == key })
        d.fetchLimit = 1
        if let existing = try? context.fetch(d).first {
            existing.categoryID = categoryID
            existing.displayMerchant = merchant
            existing.hitCount += 1
            existing.updatedAt = .now
        } else {
            context.insert(MerchantMapping(merchantKey: key, displayMerchant: merchant, categoryID: categoryID))
        }
        try? context.save()
    }
}
