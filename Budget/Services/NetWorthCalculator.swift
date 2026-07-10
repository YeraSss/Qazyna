import Foundation

/// Pure functions that convert sub-account balances into KZT net worth at the *latest* rate
/// (so net worth moves with FX). Liabilities subtract. Kept FX-agnostic via an injected
/// `rateToKZT` closure so it's trivially testable.
enum NetWorthCalculator {

    /// KZT value of one account's balance at the latest rate, sign-adjusted for liabilities.
    static func signedKZT(_ account: SubAccount, rateToKZT: (String) -> Decimal) -> Decimal {
        let kzt = Money.roundedKZT(account.cachedBalance * rateToKZT(account.currencyCode))
        return account.type.isLiability ? -kzt : kzt
    }

    /// Total net worth across accounts that are included in net worth and not archived.
    static func total(_ accounts: [SubAccount], rateToKZT: (String) -> Decimal) -> Decimal {
        accounts
            .filter { $0.includeInNetWorth && !$0.isArchived }
            .reduce(Decimal(0)) { $0 + signedKZT($1, rateToKZT: rateToKZT) }
    }

    /// Net-worth contribution of a single bank (sum of its included sub-accounts, in KZT).
    static func bankTotal(_ bank: Bank, rateToKZT: (String) -> Decimal) -> Decimal {
        total(bank.subAccounts, rateToKZT: rateToKZT)
    }
}
