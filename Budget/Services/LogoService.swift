import UIKit
import os

/// Fetches a bank's logo by its domain at runtime and caches it on-device. No logo artwork is
/// bundled in the app — logos are the property of their respective banks and are loaded for
/// identification only. Sources are tried in order (see `candidateURLs`): full-quality Brandfetch
/// if a `BRANDFETCH_CLIENT_ID` is configured, then higher-res icon.horse, then Google's favicon
/// service. Images below `minAcceptableSize` are rejected so a bank with only a tiny favicon shows
/// the clean brand-colored monogram instead of a blurry thumbnail. Offline or on failure, callers
/// fall back to the monogram.
final class LogoService {
    static let shared = LogoService()

    private let memory = NSCache<NSString, UIImage>()
    private let log = Logger(subsystem: "com.qazyna.app", category: "logo")
    private let lock = NSLock()
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private var cacheDir: URL {
        let base = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL.temporaryDirectory
        let dir = base.appendingPathComponent("BankLogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func diskURL(_ domain: String) -> URL {
        cacheDir.appendingPathComponent(domain.replacingOccurrences(of: "/", with: "_") + ".png")
    }

    /// Hand-tuned logos bundled in the asset catalog for banks whose public favicon is missing,
    /// too low-resolution, or out of date to fetch cleanly: Otbasy exposes only a 34px mark, Forte
    /// only a 16px favicon (and rebranded to a new "F"), Freedom only a blurry 32px shield. Keyed
    /// by domain; takes priority over the network fetch. Add a matching imageset
    /// (`Assets.xcassets/<name>.imageset`) to extend this to more banks.
    private static let bundledAssetNames: [String: String] = [
        "otbasybank.kz": "BankLogoOtbasy",
        "forte.kz": "BankLogoForte",
        "bankffin.kz": "BankLogoFreedom"
    ]

    /// A bundled logo for this domain, if one ships with the app. Synchronous, no network.
    func bundledLogo(for domain: String) -> UIImage? {
        guard let name = Self.bundledAssetNames[domain] else { return nil }
        return UIImage(named: name)
    }

    /// Synchronous cache lookup (memory → disk). Returns nil if not cached yet.
    func cachedLogo(for domain: String) -> UIImage? {
        guard !domain.isEmpty else { return nil }
        if let img = memory.object(forKey: domain as NSString) { return img }
        if let data = try? Data(contentsOf: diskURL(domain)), let img = UIImage(data: data) {
            memory.setObject(img, forKey: domain as NSString)
            return img
        }
        return nil
    }

    /// Cached logo, or fetch it once (de-duplicating concurrent requests for the same domain).
    /// Returns nil if unavailable (→ caller shows the monogram).
    func logo(for domain: String) async -> UIImage? {
        guard !domain.isEmpty else { return nil }
        if let cached = cachedLogo(for: domain) { return cached }

        lock.lock()
        let task: Task<UIImage?, Never>
        if let existing = inflight[domain] {
            task = existing
        } else {
            task = Task { [weak self] in await self?.fetch(domain) ?? nil }
            inflight[domain] = task
        }
        lock.unlock()

        let result = await task.value
        lock.lock(); inflight[domain] = nil; lock.unlock()
        return result
    }

    /// Reject anything below this (points) so a blurry 15–16px favicon never gets upscaled into a
    /// muddy tile — the clean brand monogram looks better than a stretched thumbnail. (32 keeps
    /// real 32px favicons like Freedom's shield while dropping the 15–16px stubs.)
    private let minAcceptableSize: CGFloat = 32

    /// Try each source in order and keep the first crisp, decodable, non-placeholder image. Sources
    /// differ in both quality and coverage, so a chain beats any single endpoint: some banks only
    /// have a good mark on one of them, and some return an undecodable SVG/ICO on another.
    private func fetch(_ domain: String) async -> UIImage? {
        for url in candidateURLs(for: domain) {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard status == 200, let img = UIImage(data: data) else { continue }
                guard min(img.size.width, img.size.height) >= minAcceptableSize else {
                    log.debug("logo \(domain, privacy: .public) too small at \(url.host ?? "", privacy: .public): \(Int(img.size.width))px")
                    continue
                }
                guard !isGeneratedPlaceholder(img) else {
                    log.debug("logo \(domain, privacy: .public) rejected generated placeholder at \(url.host ?? "", privacy: .public)")
                    continue
                }
                memory.setObject(img, forKey: domain as NSString)
                // Normalize to PNG on disk (source may be ICO/JPEG) so the disk cache always decodes.
                if let png = img.pngData() {
                    try? png.write(to: diskURL(domain), options: .atomic)
                }
                return img
            } catch {
                log.debug("logo \(domain, privacy: .public) source error: \(error.localizedDescription, privacy: .public)")
                continue
            }
        }
        log.error("no usable logo for \(domain, privacy: .public)")
        return nil
    }

    /// Some icon services return a *generated* grey monogram placeholder when they have no real
    /// logo for a domain — a flat mid-grey field with a darker grey glyph. That's worse than our
    /// own on-brand monogram, so detect it (opaque, low-saturation, uniform mid-grey corners) and
    /// reject it so the caller falls through to the next source or the monogram. Conservative: a
    /// real logo on white, on a transparent ground, or with any colour is never flagged.
    private func isGeneratedPlaceholder(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let side = 16
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &buf, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        func px(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * side + x) * 4
            return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]), Int(buf[i + 3]))
        }
        let corners = [px(0, 0), px(side - 1, 0), px(0, side - 1), px(side - 1, side - 1)]
        let first = corners[0]
        for c in corners {
            let hi = max(c.r, c.g, c.b), lo = min(c.r, c.g, c.b)
            if c.a < 250 { return false }                       // transparent ground → real logo
            if hi - lo > 16 { return false }                    // has colour → real logo
            if hi > 235 || hi < 150 { return false }            // white/near-white or dark ground → not the grey placeholder
            if abs(c.r - first.r) > 12 || abs(c.g - first.g) > 12 || abs(c.b - first.b) > 12 { return false } // non-uniform
        }
        return true                                             // flat, opaque, uniform mid-grey → generated placeholder
    }

    /// Ordered logo sources. Brandfetch (if a client ID is configured) is highest quality and best
    /// coverage; otherwise icon.horse (higher-res, aggregates multiple icon sources) then Google's
    /// favicon service (reliable PNG) act as the token-less fallback.
    private func candidateURLs(for domain: String) -> [URL] {
        var strings: [String] = []
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "BRANDFETCH_CLIENT_ID") as? String,
           !clientID.isEmpty {
            strings.append("https://cdn.brandfetch.io/\(domain)/w/256/h/256?c=\(clientID)")
        }
        strings.append("https://icon.horse/icon/\(domain)")
        strings.append("https://www.google.com/s2/favicons?sz=256&domain=\(domain)")
        return strings.compactMap(URL.init(string:))
    }
}
