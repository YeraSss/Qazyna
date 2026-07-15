import SwiftUI

/// A bank's identity tile. Shows the bank's real logo (fetched by domain and cached via
/// `LogoService`); falls back to a brand-color monogram while loading, offline, or when no
/// logo is available. No logo artwork is bundled in the app.
struct BankLogoView: View {
    let bank: Bank
    var size: CGFloat = 44

    @State private var logo: UIImage?

    var body: some View {
        Group {
            if let logo {
                Image(uiImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.16)
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .fill(Color(.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
                    )
            } else {
                monogram
            }
        }
        .task(id: bank.domain) {
            if let cached = LogoService.shared.cachedLogo(for: bank.domain) {
                logo = cached
            } else {
                logo = await LogoService.shared.logo(for: bank.domain)
            }
        }
    }

    /// Brand-color monogram fallback.
    private var monogram: some View {
        let color = Color(hex: bank.brandColorHex)
        return RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
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
