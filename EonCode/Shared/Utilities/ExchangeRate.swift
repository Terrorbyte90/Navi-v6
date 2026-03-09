import Foundation

@MainActor
class ExchangeRateService: ObservableObject {
    static let shared = ExchangeRateService()

    @Published var usdToSEK: Double = 10.5
    @Published var lastUpdated: Date?
    @Published var isLoading = false

    private let cacheKey = "exchangeRate_USD_SEK"
    private let cacheTimestampKey = "exchangeRate_timestamp"

    init() {}

    func refresh() async {}

    var isStale: Bool { false }

    func convert(usd: Double) -> Double { usd * usdToSEK }

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
