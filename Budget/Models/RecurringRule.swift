import Foundation
import SwiftData

/// A template that auto-generates transactions on a schedule (rent, subscriptions, salary).
/// `autoLog == true` posts silently on the due date; otherwise it is queued for the user to
/// confirm. `nextRun` is advanced by the `RecurringScheduler`.
@Model
final class RecurringRule {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRaw: String
    var amountOriginal: Decimal
    var currencyCode: String
    var accountID: UUID
    var categoryID: String
    var note: String?

    var frequencyRaw: String
    /// For `.custom` frequency: interval in days.
    var intervalDays: Int?
    var nextRun: Date
    var lastRun: Date?
    var autoLog: Bool
    var isActive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        kind: TransactionKind,
        amountOriginal: Decimal,
        currencyCode: String,
        accountID: UUID,
        categoryID: String,
        note: String? = nil,
        frequency: RecurrenceFrequency,
        intervalDays: Int? = nil,
        nextRun: Date,
        autoLog: Bool = true,
        isActive: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.amountOriginal = amountOriginal
        self.currencyCode = currencyCode
        self.accountID = accountID
        self.categoryID = categoryID
        self.note = note
        self.frequencyRaw = frequency.rawValue
        self.intervalDays = intervalDays
        self.nextRun = nextRun
        self.autoLog = autoLog
        self.isActive = isActive
        self.createdAt = createdAt
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    /// The next occurrence after a given date, per this rule's frequency.
    func advance(from date: Date, calendar: Calendar = .current) -> Date {
        switch frequency {
        case .daily:   return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:  return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly:  return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        case .custom:  return calendar.date(byAdding: .day, value: max(1, intervalDays ?? 30), to: date) ?? date
        }
    }
}
