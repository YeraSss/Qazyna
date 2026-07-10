import Foundation

/// A KZT-base exchange-rate snapshot. `rates[code]` = how many units of `code` equal 1 KZT
/// (the fawazahmed0 "currencies/kzt" shape). To convert a foreign amount to KZT we invert:
/// `amountKZT = amount / rates[code]`.
struct RateSnapshot: Codable, Equatable {
    var base: String
    var rateDate: String
    var fetchedAt: Date?
    var rates: [String: Double]

    /// KZT per 1 unit of `code`. Returns 1 for KZT / unknown codes (safe fallback).
    func rateToKZT(_ code: String) -> Decimal {
        let key = code.lowercased()
        if key == "kzt" { return 1 }
        guard let perKZT = rates[key], perKZT > 0 else { return 1 }
        // rates[key] = foreign units per 1 KZT  ⇒  KZT per foreign unit = 1 / rates[key]
        return Decimal(safe: 1.0 / perKZT)
    }

    var supportedCurrencyCodes: [String] {
        rates.keys.map { $0.uppercased() }.sorted()
    }

    // MARK: Loading (usable off the main actor, e.g. from the background App Intent)

    /// Best available snapshot: on-disk cache → bundled seed → KZT-only fallback.
    static func loadCurrent(cacheURL: URL = ModelContainerFactory.fxCacheURL) -> RateSnapshot {
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder.fx.decode(RateSnapshot.self, from: data) {
            return cached
        }
        if let url = Bundle.main.url(forResource: "seed_rates", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let seed = try? JSONDecoder.fx.decode(RateSnapshot.self, from: data) {
            return seed
        }
        return RateSnapshot(base: "kzt", rateDate: "fallback", fetchedAt: nil, rates: ["kzt": 1])
    }
}
