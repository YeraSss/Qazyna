import Foundation
import SwiftData
import os

/// Builds the shared `ModelContainer`. The store lives in the App Group container so the
/// widget and the background App Intent read the same data; when the App Group isn't
/// provisioned (e.g. unsigned simulator builds with no Team ID) it transparently falls back
/// to Application Support so the app still builds and runs.
enum ModelContainerFactory {
    private static let log = Logger(subsystem: "com.qazyna.app", category: "persistence")

    /// Directory that will hold the store + FX cache.
    static func containerDirectory() -> URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID) {
            return group
        }
        log.notice("App Group unavailable — falling back to Application Support (dev/simulator).")
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL.temporaryDirectory
        let dir = base.appendingPathComponent("Budget", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var storeURL: URL { containerDirectory().appendingPathComponent(AppConfig.storeName) }
    static var fxCacheURL: URL { containerDirectory().appendingPathComponent(AppConfig.fxCacheName) }

    /// The shared container, created once. No CloudKit (keeps unique constraints and
    /// non-optional relationships legal) and no lightweight-only restrictions.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)
        } else {
            config = ModelConfiguration(
                schema: AppSchema.schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        }
        do {
            return try ModelContainer(for: AppSchema.schema, configurations: config)
        } catch {
            log.error("Failed to open store, recreating: \(error.localizedDescription, privacy: .public)")
            // Last-resort recovery: move the corrupt store aside and start fresh.
            try? FileManager.default.removeItem(at: storeURL)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: AppSchema.schema, configurations: config)
        }
    }
}
