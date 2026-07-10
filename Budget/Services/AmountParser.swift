import Foundation

/// Parses the **localized text amount** that the Shortcuts "Transaction"/"Wallet" automation
/// passes into the App Intent (e.g. "1 234,56", "1,234.56", "₸ 2 990", "$12.34"). The
/// automation does not reliably pass a currency, so callers supply the expected currency and
/// we use its fraction-digit convention to resolve the ambiguous "2,990" case:
///   • KZT / 0-decimal currencies → all separators are grouping ("2 990" / "2,990" = 2990).
///   • 2-decimal currencies → the LAST separator is the decimal point.
enum AmountParser {

    /// Parse into a non-negative Decimal in the given currency. Returns nil if no digits.
    static func parse(_ raw: String, currencyCode: String) -> Decimal? {
        let fractionDigits = Money.fractionDigits(for: currencyCode)
        // Keep only digits, separators, and a leading sign.
        let negative = raw.contains("(") || raw.trimmingCharacters(in: .whitespaces).hasPrefix("-")
        let filtered = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard filtered.contains(where: \.isNumber) else { return nil }

        let value: Decimal?
        if fractionDigits == 0 {
            // No decimals expected: every separator is a thousands group.
            let digits = filtered.filter(\.isNumber)
            value = Decimal(string: digits)
        } else {
            value = parseWithDecimals(filtered)
        }
        guard let v = value else { return nil }
        return negative ? -v : v
    }

    /// For decimal currencies: the rightmost '.' or ',' is the decimal separator; others are grouping.
    private static func parseWithDecimals(_ s: String) -> Decimal? {
        let lastDot = s.lastIndex(of: ".")
        let lastComma = s.lastIndex(of: ",")
        let decimalIndex: String.Index?
        switch (lastDot, lastComma) {
        case let (d?, c?): decimalIndex = d > c ? d : c
        case let (d?, nil): decimalIndex = d
        case let (nil, c?): decimalIndex = c
        default: decimalIndex = nil
        }

        guard let di = decimalIndex else {
            return Decimal(string: s.filter(\.isNumber))
        }
        // Only treat it as a decimal separator if it looks like one (<= 2 trailing digits).
        let fraction = s[s.index(after: di)...].filter(\.isNumber)
        if fraction.count > 2 {
            // Too many trailing digits → it was actually grouping; treat whole thing as integer.
            return Decimal(string: s.filter(\.isNumber))
        }
        let intPart = s[..<di].filter(\.isNumber)
        let normalized = intPart + "." + fraction
        return Decimal(string: normalized)
    }
}
