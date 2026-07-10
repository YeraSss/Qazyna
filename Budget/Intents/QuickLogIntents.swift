import AppIntents
import Foundation

/// Opens the app straight to the quick-add sheet (Siri / Spotlight / Action Button / widget).
struct OpenQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var description = IntentDescription("Opens Qazyna to quickly add a transaction.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickAddRouter.shared.requestOpen()
        return .result()
    }
}

/// Bridges an intent request to the SwiftUI hierarchy so the quick-add sheet can be presented
/// when the app opens (cold or warm). Also readable via a persisted flag for cold launches.
@MainActor
final class QuickAddRouter: ObservableObject {
    static let shared = QuickAddRouter()
    @Published var shouldOpenQuickAdd = false

    private let flagKey = "pendingQuickAdd"

    func requestOpen() {
        shouldOpenQuickAdd = true
        UserDefaults.standard.set(true, forKey: flagKey)
    }

    /// Called on scene activation to catch cold-launch requests.
    func consumePendingIfNeeded() {
        if UserDefaults.standard.bool(forKey: flagKey) {
            shouldOpenQuickAdd = true
            UserDefaults.standard.set(false, forKey: flagKey)
        }
    }

    func clear() {
        shouldOpenQuickAdd = false
        UserDefaults.standard.set(false, forKey: flagKey)
    }
}
