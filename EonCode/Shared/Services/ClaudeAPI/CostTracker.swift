import Foundation

// MARK: - CostTracker
// Persistent, cumulative cost tracking across all conversations and sessions.

@MainActor
final class CostTracker: ObservableObject {
    static let shared = CostTracker()

    // MARK: - Published state

    @Published private(set) var totalUSD: Double = 0
    @Published private(set) var sessionUSD: Double = 0
    @Published private(set) var totalRequests: Int = 0
    @Published private(set) var sessionRequests: Int = 0
    @Published private(set) var totalInputTokens: Int = 0
    @Published private(set) var totalOutputTokens: Int = 0
    @Published private(set) var totalCacheReadTokens: Int = 0
    @Published private(set) var lastRequestUSD: Double = 0
    @Published private(set) var lastRequestModel: ClaudeModel? = nil
    @Published private(set) var lastRequestTokens: TokenUsage? = nil
    @Published var monthlyUSD: Double = 0
    private var monthlyResetDate: Date = Date()

    // MARK: - Persistence keys

    private enum Keys {
        static let totalUSD = "costTracker.totalUSD"
        static let totalRequests = "costTracker.totalRequests"
        static let totalInputTokens = "costTracker.totalInputTokens"
        static let totalOutputTokens = "costTracker.totalOutputTokens"
        static let totalCacheReadTokens = "costTracker.totalCacheReadTokens"
        static let monthlyUSD = "costTracker.monthlyUSD"
        static let monthlyResetDate = "costTracker.monthlyResetDate"
    }

    private init() {
        load()
    }

    // MARK: - Record a completed request

    func record(usage: TokenUsage, model: ClaudeModel) {
        let (usd, _) = CostCalculator.shared.calculate(usage: usage, model: model)

        totalUSD += usd
        sessionUSD += usd
        totalRequests += 1
        sessionRequests += 1
        totalInputTokens += usage.inputTokens
        totalOutputTokens += usage.outputTokens
        totalCacheReadTokens += usage.cacheReadInputTokens ?? 0
        lastRequestUSD = usd
        lastRequestModel = model
        lastRequestTokens = usage

        record(usd: usd)
        save()
    }

    // MARK: - Record arbitrary USD cost (e.g. from server usage)

    func record(usd: Double) {
        checkMonthlyReset()
        monthlyUSD += usd
        save()
    }

    // MARK: - Record media generation cost

    func recordMediaCost(usd: Double, model: String) {
        totalUSD += usd
        sessionUSD += usd
        record(usd: usd)
        save()
    }

    // MARK: - Monthly bucketing

    private func checkMonthlyReset() {
        let cal = Calendar.current
        let now = Date()
        if !cal.isDate(now, equalTo: monthlyResetDate, toGranularity: .month) {
            monthlyUSD = 0
            monthlyResetDate = now
        }
    }

    // MARK: - Reset session (call on app foreground)

    func resetSession() {
        sessionUSD = 0
        sessionRequests = 0
    }

    // MARK: - Reset all (for testing / user request)

    func resetAll() {
        totalUSD = 0
        sessionUSD = 0
        monthlyUSD = 0
        totalRequests = 0
        sessionRequests = 0
        totalInputTokens = 0
        totalOutputTokens = 0
        totalCacheReadTokens = 0
        lastRequestUSD = 0
        lastRequestModel = nil
        lastRequestTokens = nil
        monthlyResetDate = Date()
        save()
    }

    // MARK: - Formatted helpers

    var totalSEK: Double { totalUSD * ExchangeRateService.shared.usdToSEK }
    var sessionSEK: Double { sessionUSD * ExchangeRateService.shared.usdToSEK }
    var lastRequestSEK: Double { lastRequestUSD * ExchangeRateService.shared.usdToSEK }
    var monthlySEK: Double { monthlyUSD * ExchangeRateService.shared.usdToSEK }

    func formattedTotal() -> String { formatSEK(totalSEK) + " (\(formatUSD(totalUSD)))" }
    func formattedSession() -> String { formatSEK(sessionSEK) + " (\(formatUSD(sessionUSD)))" }
    func formattedMonthly() -> String { formatSEK(monthlySEK) + " (\(formatUSD(monthlyUSD)))" }
    func formattedLast() -> String {
        guard lastRequestUSD > 0 else { return "—" }
        return formatSEK(lastRequestSEK) + " (\(formatUSD(lastRequestUSD)))"
    }

    private func formatSEK(_ v: Double) -> String {
        v < 0.01 ? "< 0.01 kr" : String(format: "%.2f kr", v)
    }
    private func formatUSD(_ v: Double) -> String {
        v < 0.0001 ? "< $0.0001" : String(format: "$%.4f", v)
    }

    // MARK: - Persistence

    private func save() {
        let ud = UserDefaults.standard
        ud.set(totalUSD, forKey: Keys.totalUSD)
        ud.set(totalRequests, forKey: Keys.totalRequests)
        ud.set(totalInputTokens, forKey: Keys.totalInputTokens)
        ud.set(totalOutputTokens, forKey: Keys.totalOutputTokens)
        ud.set(totalCacheReadTokens, forKey: Keys.totalCacheReadTokens)
        ud.set(monthlyUSD, forKey: Keys.monthlyUSD)
        ud.set(monthlyResetDate.timeIntervalSince1970, forKey: Keys.monthlyResetDate)
    }

    private func load() {
        let ud = UserDefaults.standard
        totalUSD = ud.double(forKey: Keys.totalUSD)
        totalRequests = ud.integer(forKey: Keys.totalRequests)
        totalInputTokens = ud.integer(forKey: Keys.totalInputTokens)
        totalOutputTokens = ud.integer(forKey: Keys.totalOutputTokens)
        totalCacheReadTokens = ud.integer(forKey: Keys.totalCacheReadTokens)
        monthlyUSD = ud.double(forKey: Keys.monthlyUSD)
        let resetInterval = ud.double(forKey: Keys.monthlyResetDate)
        monthlyResetDate = resetInterval > 0 ? Date(timeIntervalSince1970: resetInterval) : Date()
    }
}
