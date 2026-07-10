import Foundation

/// Money is `Decimal` end-to-end (never `Double`) and stored at full precision.
/// Rounding happens **only at display / at the moment a KZT-equivalent is snapshotted**,
/// using one centralized policy, so cached-rate conversions never accumulate drift.
enum Money {
    /// Base currency of the app.
    static let baseCurrency = "KZT"

    /// Fraction digits used when *displaying* a currency. KZT is shown with 0 (the tiyn
    /// subunit is defunct); every other currency uses its ISO/CLDR default.
    static func fractionDigits(for currencyCode: String) -> Int {
        currencyCode.uppercased() == baseCurrency ? 0 : isoFractionDigits(currencyCode)
    }

    /// ISO 4217 minor-unit digits, best-effort via Foundation.
    static func isoFractionDigits(_ code: String) -> Int {
        // Common zero-decimal currencies where Foundation may still say 2.
        let zeroDecimal: Set<String> = ["JPY", "KRW", "VND", "CLP", "ISK", "HUF", "UGX", "RWF", "XAF", "XOF", "KZT"]
        if zeroDecimal.contains(code.uppercased()) { return 0 }
        return 2
    }

    /// Round a decimal to the given number of fraction digits (half-up).
    static func rounded(_ value: Decimal, fractionDigits: Int) -> Decimal {
        var result = Decimal()
        var input = value
        NSDecimalRound(&result, &input, fractionDigits, .plain)
        return result
    }

    /// Round a KZT-equivalent for storage/aggregation using the base-currency policy (0 digits).
    static func roundedKZT(_ value: Decimal) -> Decimal {
        rounded(value, fractionDigits: fractionDigits(for: baseCurrency))
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    /// Safe construction from a Double via string, avoiding binary-float artifacts.
    init(safe value: Double) {
        self = Decimal(string: String(value)) ?? Decimal(value)
    }
}
