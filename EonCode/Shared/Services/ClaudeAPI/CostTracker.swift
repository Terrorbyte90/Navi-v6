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

    // MARK: - Persistence keys

    private enum Keys {
        static let totalUSD = "costTracker.totalUSD"
        static let totalRequests = "costTracker.totalRequests"
        static let totalInputTokens = "costTracker.totalInputTokens"
        static let totalOutputTokens = "costTracker.totalOutputTokens"
        static let totalCacheReadTokens = "costTracker.totalCacheReadTokens"
    }

    private init() {
        load()
    }

    // MARK: - Record a completed request (no-op — cost tracking disabled)

    func record(usage: TokenUsage, model: ClaudeModel) {}

    // MARK: - Record media generation cost (no-op)

    func recordMediaCost(usd: Double, model: String) {}

    // MARK: - Reset session (call on app foreground)

    func resetSession() {
        sessionUSD = 0
        sessionRequests = 0
    }

    // MARK: - Reset all (for testing / user request)

    func resetAll() {
        totalUSD = 0
        sessionUSD = 0
        totalRequests = 0
        sessionRequests = 0
        totalInputTokens = 0
        totalOutputTokens = 0
        totalCacheReadTokens = 0
        lastRequestUSD = 0
        lastRequestModel = nil
        lastRequestTokens = nil
        save()
    }

    // MARK: - Formatted helpers

    var totalSEK: Double { totalUSD * ExchangeRateService.shared.usdToSEK }
    var sessionSEK: Double { sessionUSD * ExchangeRateService.shared.usdToSEK }
    var lastRequestSEK: Double { lastRequestUSD * ExchangeRateService.shared.usdToSEK }

    func formattedTotal() -> String { formatSEK(totalSEK) + " (\(formatUSD(totalUSD)))" }
    func formattedSession() -> String { formatSEK(sessionSEK) + " (\(formatUSD(sessionUSD)))" }
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
    }

    private func load() {
        let ud = UserDefaults.standard
        totalUSD = ud.double(forKey: Keys.totalUSD)
        totalRequests = ud.integer(forKey: Keys.totalRequests)
        totalInputTokens = ud.integer(forKey: Keys.totalInputTokens)
        totalOutputTokens = ud.integer(forKey: Keys.totalOutputTokens)
        totalCacheReadTokens = ud.integer(forKey: Keys.totalCacheReadTokens)
    }
}
