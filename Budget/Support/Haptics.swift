import UIKit

/// Lightweight haptic feedback helpers for key actions (add, transfer, warnings).
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
