import Foundation

/// Widget-side copy of the snapshot the app publishes to the App Group. Kept as a small,
/// dependency-free struct so the widget extension needn't compile the app's model layer.
struct WidgetSnapshot: Codable {
    var netWorthKZT: Double
    var monthSpentKZT: Double
    var monthIncomeKZT: Double
    var topBudgetName: String?
    var topBudgetRatio: Double
    var updatedAt: Date

    static let appGroupID = "group.com.qazyna.app"
    static let filename = "widget_snapshot.json"

    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(netWorthKZT: 0, monthSpentKZT: 0, monthIncomeKZT: 0,
                       topBudgetName: nil, topBudgetRatio: 0, updatedAt: Date())
    }

    /// Load the latest snapshot from the App Group container (nil → placeholder).
    static func load() -> WidgetSnapshot {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return placeholder
        }
        let url = dir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return placeholder
        }
        return snap
    }

    /// KZT string like "1 817 385 ₸".
    func kzt(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = " "
        let n = f.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(n) ₸"
    }
}
