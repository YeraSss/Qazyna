import Foundation

/// Formats `Decimal` money for display.
///
/// KZT is pinned to the `kk_KZ` locale so it renders `1 234 567 ₸` (symbol trailing,
/// space grouping, 0 fraction digits) regardless of the device locale. Foreign currencies
/// use their own CLDR defaults so cents are never wrongly stripped from USD/EUR/etc.
enum CurrencyFormatter {
    private static let kzLocale = Locale(identifier: "kk_KZ")

    static func string(_ amount: Decimal, currencyCode: String) -> String {
        let code = currencyCode.uppercased()
        let digits = Money.fractionDigits(for: code)
        if code == Money.baseCurrency {
            return amount.formatted(
                .currency(code: code)
                    .precision(.fractionLength(digits))
                    .locale(kzLocale)
            )
        }
        return amount.formatted(
            .currency(code: code)
                .precision(.fractionLength(digits))
        )
    }

    /// KZT convenience (the base-currency total shown across most of the app).
    static func kzt(_ amount: Decimal) -> String {
        string(amount, currencyCode: Money.baseCurrency)
    }

    /// A compact form for chart axis labels, e.g. "1.2M ₸", "350K ₸".
    static func compactKZT(_ amount: Decimal) -> String {
        let value = amount.doubleValue
        let sign = value < 0 ? "-" : ""
        let abs = Swift.abs(value)
        let symbol = "₸"
        switch abs {
        case 1_000_000...:
            return "\(sign)\(trim(abs / 1_000_000))M \(symbol)"
        case 1_000...:
            return "\(sign)\(trim(abs / 1_000))K \(symbol)"
        default:
            return "\(sign)\(Int(abs)) \(symbol)"
        }
    }

    private static func trim(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }
}
