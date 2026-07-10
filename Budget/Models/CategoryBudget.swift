import Foundation
import SwiftData

/// A monthly spending limit for a category (in KZT). `thresholds` are the fractions at
/// which a warning fires (default 80% and 100%), configurable per budget.
@Model
final class CategoryBudget {
    @Attribute(.unique) var id: UUID
    /// One current budget per category (v1) — unique on the category slug.
    @Attribute(.unique) var categoryID: String
    var limitKZT: Decimal
    var thresholds: [Double]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        categoryID: String,
        limitKZT: Decimal,
        thresholds: [Double] = [0.8, 1.0],
        createdAt: Date = .now
    ) {
        self.id = id
        self.categoryID = categoryID
        self.limitKZT = limitKZT
        self.thresholds = thresholds.sorted()
        self.createdAt = createdAt
    }
}
