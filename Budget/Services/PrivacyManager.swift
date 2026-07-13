import SwiftUI

/// Controls whether monetary balances are hidden on screen. When `enabled` (default),
/// balances render redacted until the user taps to reveal; the reveal is transient and
/// resets when the app goes to the background, so a glance at a locked-away phone shows nothing.
@MainActor
final class PrivacyManager: ObservableObject {
    /// Whether the hide-balances feature is on (persisted). Default: on.
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.key) }
    }
    /// Transient: are balances currently revealed this session?
    @Published var revealed = false

    private static let key = "hideBalances"

    init() {
        enabled = UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true
    }

    /// True when amounts should be masked right now.
    var isHidden: Bool { enabled && !revealed }

    /// Icon reflecting current state (for the toolbar toggle).
    var eyeSymbol: String { isHidden ? "eye.slash" : "eye" }

    func toggleReveal() {
        guard enabled else { return }
        withAnimation(.easeInOut(duration: 0.2)) { revealed.toggle() }
        Haptics.selection()
    }

    /// Re-hide (called when the app backgrounds).
    func rehide() { revealed = false }

    /// A **fixed-length** mask that reveals neither the value nor its magnitude — every hidden
    /// amount renders identically, so you can't infer size from the width.
    func masked(_ amount: String) -> String { isHidden ? "••••••" : amount }
}
