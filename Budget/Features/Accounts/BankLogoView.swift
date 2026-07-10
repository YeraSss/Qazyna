import SwiftUI

/// A bank's identity tile. Phase 1 always renders the brand-color monogram fallback; Phase 6
/// wires the runtime logo API on top with this as the guaranteed fallback. No official bank
/// logo artwork is ever bundled in the app.
struct BankLogoView: View {
    let bank: Bank
    var size: CGFloat = 44

    var body: some View {
        let color = Color(hex: bank.brandColorHex)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(bank.monogram)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(color.readableForeground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}
