import Foundation
import SwiftData

/// Posts due recurring transactions. `autoLog` rules post silently (catching up on any missed
/// periods); confirm-first rules are surfaced as "due" for the user to log or skip. Runs at
/// launch and after edits. Idempotent via a per-occurrence dedupKey.
enum RecurringScheduler {

    /// Auto-post all due `autoLog` rules. Returns the number of transactions posted.
    @discardableResult
    static func runAutoLog(in context: ModelContext, now: Date = .now) -> Int {
        let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
        var posted = 0
        for rule in rules where rule.isActive && rule.autoLog {
            var guardCount = 0
            while rule.nextRun <= now && guardCount < 60 {
                postOccurrence(rule, on: rule.nextRun, in: context)
                rule.lastRun = rule.nextRun
                rule.nextRun = rule.advance(from: rule.nextRun)
                posted += 1
                guardCount += 1
            }
        }
        if posted > 0 { try? context.save() }
        return posted
    }

    /// Confirm-first rules that are currently due.
    static func dueForConfirmation(in context: ModelContext, now: Date = .now) -> [RecurringRule] {
        let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
        return rules.filter { $0.isActive && !$0.autoLog && $0.nextRun <= now }
    }

    /// Upcoming (not-yet-due) active rules, soonest first.
    static func upcoming(in context: ModelContext, now: Date = .now) -> [RecurringRule] {
        let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
        return rules.filter { $0.isActive && $0.nextRun > now }.sorted { $0.nextRun < $1.nextRun }
    }

    /// Manually confirm one occurrence of a confirm-first rule (posts + advances).
    static func confirm(_ rule: RecurringRule, in context: ModelContext) {
        postOccurrence(rule, on: rule.nextRun, in: context)
        rule.lastRun = rule.nextRun
        rule.nextRun = rule.advance(from: rule.nextRun)
        try? context.save()
    }

    /// Skip one occurrence without posting.
    static func skip(_ rule: RecurringRule, in context: ModelContext) {
        rule.nextRun = rule.advance(from: rule.nextRun)
        try? context.save()
    }

    private static func postOccurrence(_ rule: RecurringRule, on date: Date, in context: ModelContext) {
        let rate = RateSnapshot.loadCurrent().rateToKZT(rule.currencyCode)
        let dedupKey = "recur-\(rule.id.uuidString)-\(DateKeys.dayKey(date))"
        let draft = TransactionDraft(
            dedupKey: dedupKey, kind: rule.kind, amountOriginal: rule.amountOriginal,
            currencyCode: rule.currencyCode, fxRateToKZT: rate, date: date,
            accountID: rule.accountID, categoryID: rule.categoryID,
            merchant: rule.title, note: rule.note, source: .recurring
        )
        try? Ledger.insert(draft, in: context)
    }
}
