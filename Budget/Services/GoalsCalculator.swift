import Foundation
import SwiftData

/// Computes savings-goal progress and a projected completion date. Saved amount comes from
/// the linked account's KZT balance (or a manual amount). Projection uses the trailing
/// average monthly net (income − expense) as a proxy for saving capacity.
enum GoalsCalculator {

    struct Projection {
        let savedKZT: Decimal
        let targetKZT: Decimal
        let remainingKZT: Decimal
        var ratio: Double { targetKZT > 0 ? min(1, savedKZT.doubleValue / targetKZT.doubleValue) : 0 }
        let projectedDate: Date?
        let requiredMonthly: Decimal?   // to hit an explicit target date
        var isComplete: Bool { savedKZT >= targetKZT }
    }

    static func projection(for goal: SavingsGoal, in context: ModelContext,
                           rateToKZT: (String) -> Decimal, now: Date = .now) -> Projection {
        let saved: Decimal
        if let accountID = goal.linkedAccountID,
           let acct = try? context.fetch(FetchDescriptor<SubAccount>(predicate: #Predicate { $0.id == accountID })).first {
            saved = Money.roundedKZT(acct.cachedBalance * rateToKZT(acct.currencyCode))
        } else {
            saved = goal.manualSavedKZT
        }
        let remaining = max(0, goal.targetKZT - saved)

        // Average monthly net over trailing 3 months as saving capacity.
        let monthly = AnalyticsData.monthlySeries(endingAt: DateKeys.currentMonthKey(), count: 3, in: context)
        let nets = monthly.map { $0.incomeKZT - $0.expenseKZT }
        let avgNet = nets.isEmpty ? Decimal(0) : nets.reduce(0, +) / Decimal(nets.count)

        var projectedDate: Date?
        if remaining > 0, avgNet > 0 {
            let months = (remaining.doubleValue / avgNet.doubleValue).rounded(.up)
            projectedDate = Calendar.current.date(byAdding: .month, value: Int(months), to: now)
        } else if remaining == 0 {
            projectedDate = now
        }

        var requiredMonthly: Decimal?
        if let target = goal.targetDate, remaining > 0 {
            let months = Calendar.current.dateComponents([.month], from: now, to: target).month ?? 0
            if months > 0 { requiredMonthly = Money.roundedKZT(remaining / Decimal(months)) }
        }

        return Projection(savedKZT: saved, targetKZT: goal.targetKZT, remainingKZT: remaining,
                          projectedDate: projectedDate, requiredMonthly: requiredMonthly)
    }
}
