import Foundation
import SwiftData

/// Single source of truth for the model set, used identically by the app, and later the
/// widget and background App Intent, so every process opens the same store schema.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Bank.self,
        SubAccount.self,
        Category.self,
        TransactionRecord.self,
        TransferRecord.self,
        BalanceAdjustment.self,
        CategoryBudget.self,
        SavingsGoal.self,
        RecurringRule.self,
        MerchantMapping.self,
        CardMapping.self,
        DailyRollup.self,
        MonthlyRollup.self,
        CategoryMonthlyRollup.self,
        NetWorthSnapshot.self
    ]

    static var schema: Schema { Schema(models) }
}
