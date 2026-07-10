import Foundation

/// Shared configuration used by the app, the widget extension, and the background App Intent.
enum AppConfig {
    /// App Group identifier. Must match the entitlement on the app + widget targets.
    /// Change this together with the entitlements file and your Team ID (see README).
    static let appGroupID = "group.com.qazyna.app"

    /// SQLite store filename inside the resolved container.
    static let storeName = "Budget.store"

    /// FX snapshot filename cached in the resolved container.
    static let fxCacheName = "fx_rates.json"
}
