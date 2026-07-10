import Foundation
import os

/// Provides KZT conversion rates with an offline-first fallback chain:
/// cached snapshot → bundled seed → KZT=1. Phase 1 loads the seed / cache synchronously;
/// `refresh()` (Phase 2) fetches a fresh snapshot from the network and updates the cache.
@MainActor
final class FXRateService: ObservableObject {
    @Published private(set) var snapshot: RateSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let cacheURL: URL
    private let log = Logger(subsystem: "com.qazyna.app", category: "fx")

    init(cacheURL: URL = ModelContainerFactory.fxCacheURL) {
        self.cacheURL = cacheURL
        self.snapshot = Self.loadCached(cacheURL) ?? Self.loadSeed() ?? RateSnapshot(base: "kzt", rateDate: "seed", fetchedAt: nil, rates: ["kzt": 1])
    }

    // MARK: Conversion

    func rateToKZT(_ code: String) -> Decimal { snapshot.rateToKZT(code) }

    func convertToKZT(_ amount: Decimal, from code: String) -> Decimal {
        Money.roundedKZT(amount * snapshot.rateToKZT(code))
    }

    var supportedCurrencyCodes: [String] { snapshot.supportedCurrencyCodes }

    /// True when the cached snapshot is from an earlier calendar day than today.
    var isStale: Bool {
        guard let fetched = snapshot.fetchedAt else { return true }
        return !Calendar.current.isDateInToday(fetched)
    }

    var ratesAsOfText: String {
        if let fetched = snapshot.fetchedAt {
            return "Rates as of \(fetched.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Offline seed rates (\(snapshot.rateDate))"
    }

    // MARK: Loading

    private static func loadCached(_ url: URL) -> RateSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.fx.decode(RateSnapshot.self, from: data)
    }

    private static func loadSeed() -> RateSnapshot? {
        guard let url = Bundle.main.url(forResource: "seed_rates", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.fx.decode(RateSnapshot.self, from: data)
    }

    func persist(_ snapshot: RateSnapshot) {
        if let data = try? JSONEncoder.fx.encode(snapshot) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: Network refresh (Phase 2 wires this into launch + pull-to-refresh)

    /// Primary + fallback keyless CC0 endpoints (fawazahmed0 Currency API), KZT base.
    private static let endpoints = [
        "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/kzt.min.json",
        "https://latest.currency-api.pages.dev/v1/currencies/kzt.min.json"
    ]

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        for endpoint in Self.endpoints {
            guard let url = URL(string: endpoint) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                if let fresh = Self.parseRemote(data) {
                    snapshot = fresh
                    persist(fresh)
                    log.notice("FX refreshed from \(endpoint, privacy: .public)")
                    return
                }
            } catch {
                log.error("FX fetch failed (\(endpoint, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                continue
            }
        }
        lastError = "Couldn't refresh rates — using \(snapshot.fetchedAt == nil ? "seed" : "cached") rates."
    }

    /// Remote shape: `{ "date": "2026-07-09", "kzt": { "usd": 0.0019, ... } }`.
    private static func parseRemote(_ data: Data) -> RateSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let date = obj["date"] as? String,
              let map = obj["kzt"] as? [String: Any] else { return nil }
        var rates: [String: Double] = ["kzt": 1]
        for (k, v) in map {
            if let d = v as? Double { rates[k] = d }
            else if let n = v as? NSNumber { rates[k] = n.doubleValue }
        }
        return RateSnapshot(base: "kzt", rateDate: date, fetchedAt: Date(), rates: rates)
    }
}

extension JSONDecoder {
    static var fx: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
extension JSONEncoder {
    static var fx: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
