import UIKit
import os

/// Fetches a bank's logo by its domain at runtime and caches it on-device. No logo artwork is
/// bundled in the app — logos are the property of their respective banks and are loaded for
/// identification only. If a `BRANDFETCH_CLIENT_ID` is set in Info.plist, full-quality logos
/// come from Brandfetch; otherwise a favicon service provides a recognizable mark. Offline or
/// on failure, callers fall back to the brand-colored monogram.
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

    private func fetch(_ domain: String) async -> UIImage? {
        guard let url = remoteURL(for: domain) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200, data.count > 100, let img = UIImage(data: data) else {
                log.error("logo \(domain, privacy: .public) failed: status=\(status) bytes=\(data.count)")
                return nil
            }
            memory.setObject(img, forKey: domain as NSString)
            try? data.write(to: diskURL(domain), options: .atomic)
            return img
        } catch {
            log.error("logo \(domain, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func remoteURL(for domain: String) -> URL? {
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "BRANDFETCH_CLIENT_ID") as? String,
           !clientID.isEmpty {
            return URL(string: "https://cdn.brandfetch.io/\(domain)/w/256/h/256?c=\(clientID)")
        }
        // No-config fallback: a favicon service returns the bank's icon (recognizable, low-res).
        return URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(domain)")
    }
}
