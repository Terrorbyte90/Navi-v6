import Foundation

@MainActor
class ExchangeRateService: ObservableObject {
    static let shared = ExchangeRateService()

    @Published var usdToSEK: Double = 10.5
    @Published var lastUpdated: Date?
    @Published var isLoading = false

    private let cacheKey = "exchangeRate_USD_SEK"
    private let cacheTimestampKey = "exchangeRate_timestamp"
    private let stalenessInterval: TimeInterval = 24 * 60 * 60   // 24 hours
    private let apiURL = "https://open.er-api.com/v6/latest/USD"

    private init() {
        loadFromCache()
        if isStale { Task { await refresh() } }
    }

    // MARK: - Staleness

    var isStale: Bool {
        guard let ts = lastUpdated else { return true }
        return Date().timeIntervalSince(ts) > stalenessInterval
    }

    // MARK: - Refresh from network

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: apiURL) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)
            guard response.result == "success", let rate = response.rates["SEK"] else { return }

            usdToSEK = rate
            lastUpdated = Date()
            saveToCache(rate: rate)
        } catch {
            NaviLog.warning("ExchangeRateService: kunde inte hämta valutakurs — använder cachad \(usdToSEK)")
        }
    }

    // MARK: - Conversion

    func convert(usd: Double) -> Double {
        if isStale { Task { await refresh() } }
        return usd * usdToSEK
    }

    func formatSEK(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.numberStyle = .currency
        f.currencyCode = "SEK"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
        return f.string(from: NSNumber(value: amount)) ?? "\(amount) SEK"
    }

    // MARK: - Cache

    private func loadFromCache() {
        if let rate = UserDefaults.standard.object(forKey: cacheKey) as? Double {
            usdToSEK = rate
        }
        if let ts = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date {
            lastUpdated = ts
        }
    }

    private func saveToCache(rate: Double) {
        UserDefaults.standard.set(rate, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
    }
}

private struct ExchangeRateResponse: Codable {
    let result: String
    let rates: [String: Double]
}
