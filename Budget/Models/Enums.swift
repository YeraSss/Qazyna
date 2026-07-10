import Foundation
import SwiftUI

/// Enums are stored on `@Model` rows as their **raw String** (`typeRaw`, `kindRaw`, …)
/// because SwiftData `#Predicate` filtering on `Codable` enums has historically been flaky.
/// The typed accessor is a computed convenience only.

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case card, deposit, savings, cash, asset, loan
    var id: String { rawValue }

    var isLiability: Bool { self == .loan }

    var displayName: String {
        switch self {
        case .card: return "Card"
        case .deposit: return "Deposit"
        case .savings: return "Savings"
        case .cash: return "Cash"
        case .asset: return "Asset / Investment"
        case .loan: return "Loan / Liability"
        }
    }

    var systemImage: String {
        switch self {
        case .card: return "creditcard.fill"
        case .deposit: return "banknote.fill"
        case .savings: return "lock.fill"
        case .cash: return "dollarsign.circle.fill"
        case .asset: return "chart.line.uptrend.xyaxis"
        case .loan: return "arrow.down.circle.fill"
        }
    }
}

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var displayName: String { self == .expense ? "Expense" : "Income" }
    /// Sign applied to a sub-account balance.
    var balanceSign: Int { self == .expense ? -1 : 1 }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly, custom
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .custom: return "Custom"
        }
    }
}

/// How a transaction entered the ledger. Drives the capture-source tag and dedup strategy.
enum EntrySource: String, Codable, CaseIterable {
    case manual, tapToTrack, widget, nlParser, receiptOCR, statementOCR, csvImport, recurring
    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .tapToTrack: return "Tap to Track"
        case .widget: return "Quick Log"
        case .nlParser: return "Text"
        case .receiptOCR: return "Receipt"
        case .statementOCR: return "Statement"
        case .csvImport: return "Import"
        case .recurring: return "Recurring"
        }
    }
}
