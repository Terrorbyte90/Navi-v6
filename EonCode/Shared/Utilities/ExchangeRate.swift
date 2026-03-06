import Foundation

@MainActor
class ExchangeRateService: ObservableObject {
    static let shared = ExchangeRateService()

    @Published var usdToSEK: Double = 10.5
    @Published var lastUpdated: Date?
    @Published var isLoading = false

    private let cacheKey = "exchangeRate_USD_SEK"
    private let cacheTimestampKey = "exchangeRate_timestamp"

    init() {
        loadCached()
        Task { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: Constants.API.exchangeRateURL)!)
            let response = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)
            if let rate = response.rates["SEK"] {
                usdToSEK = rate
                lastUpdated = Date()
                UserDefaults.standard.set(rate, forKey: cacheKey)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
            }
        } catch {
            // Keep cached value
        }
    }

    private func loadCached() {
        let cached = UserDefaults.standard.double(forKey: cacheKey)
        if cached > 0 { usdToSEK = cached }
        if let ts = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Double {
            lastUpdated = Date(timeIntervalSince1970: ts)
        }
    }

    var isStale: Bool {
        guard let lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 24 * 60 * 60
    }

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
}

private struct ExchangeRateResponse: Codable {
    let result: String
    let rates: [String: Double]
}
