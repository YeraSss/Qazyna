import SwiftUI

/// Renders a logo for a domain (fetched + cached via `LogoService`), falling back to a
/// brand-color monogram while loading, offline, or when no logo is available. Reused by both
/// saved banks and the Add-Bank picker (which has presets, not `Bank` objects yet).
struct LogoTile: View {
    let domain: String
    let color: Color
    let initials: String
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
                    // Always a white chip: most logos are drawn for a white ground, and many
                    // favicons carry a baked-in white square. On a dark (systemBackground) tile
                    // that square showed as visible white corners in dark mode — a fixed white
                    // ground blends it away and reads as an intentional icon in both appearances.
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .strokeBorder(.black.opacity(0.10), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initials)
                            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                            .foregroundStyle(color.readableForeground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    )
            }
        }
        .task(id: domain) {
            guard !domain.isEmpty else { return }
            // Bundled logo first (crisp, offline, correct on first launch), then network, then monogram.
            if let bundled = LogoService.shared.bundledLogo(for: domain) {
                logo = bundled
            } else if let cached = LogoService.shared.cachedLogo(for: domain) {
                logo = cached
            } else {
                logo = await LogoService.shared.logo(for: domain)
            }
        }
    }
}

/// A saved bank's identity tile.
struct BankLogoView: View {
    let bank: Bank
    var size: CGFloat = 44

    var body: some View {
        LogoTile(domain: bank.domain, color: Color(hex: bank.brandColorHex),
                 initials: bank.monogram, size: size)
    }
}
