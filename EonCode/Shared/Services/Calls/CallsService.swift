import Foundation
import Combine

// MARK: - CallsService
// All communication with navi-brain /calls* and /telephony* endpoints.

@MainActor
final class CallsService: ObservableObject {
    static let shared = CallsService()

    // ── Published state ──────────────────────────────────────
    @Published var calls:          [Call]          = []
    @Published var scheduled:      [ScheduledCall] = []
    @Published var liveCalls:      [Call]          = []
    @Published var stats:          CallStats?
    @Published var isLoading      = false
    @Published var isConfigured   = false
    @Published var lastError:      String?

    // ── Live polling ─────────────────────────────────────────
    private var liveTimer:  AnyCancellable?
    private var statsTimer: AnyCancellable?

    private init() {}

    // ── Base URL & auth ──────────────────────────────────────

    private var baseURL: String { NaviBrainService.baseURL }
    private let apiKey = "navi-brain-2026"

    private func headers() -> [String: String] {
        ["X-API-Key": apiKey, "Content-Type": "application/json"]
    }

    // ── Generic request helper ───────────────────────────────

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in headers() { req.setValue(v, forHTTPHeaderField: k) }
        if let b = body { req.httpBody = try JSONSerialization.data(withJSONObject: b) }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let msg  = String(data: data, encoding: .utf8) ?? "Okänt fel"
            throw NSError(domain: "CallsService", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(code): \(msg.prefix(200))"])
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private func requestVoid(path: String, method: String = "POST", body: [String: Any]? = nil) async throws {
        let _: [String: String] = try await request(path: path, method: method, body: body)
    }

    // ── Setup ────────────────────────────────────────────────

    func setupTelephony() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let result: [String: AnyCodable] = try await request(path: "/telephony/setup", method: "POST")
            isConfigured = (result["ok"] as? Bool) == true
                || result["configured"] != nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func fetchConfig() async {
        do {
            struct Config: Decodable {
                let configured: Bool
                let webhookUrl: String?
            }
            let cfg: Config = try await request(path: "/telephony/config")
            isConfigured = cfg.configured
        } catch {}
    }

    // ── Refresh all ──────────────────────────────────────────

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.fetchCalls() }
            g.addTask { await self.fetchScheduled() }
            g.addTask { await self.fetchStats() }
            g.addTask { await self.fetchConfig() }
        }
    }

    // ── Call history ─────────────────────────────────────────

    func fetchCalls(limit: Int = 50) async {
        do {
            let resp: CallsResponse = try await request(path: "/calls?limit=\(limit)")
            calls = resp.calls
        } catch {
            lastError = error.localizedDescription
        }
    }

    func fetchCall(_ id: String) async -> Call? {
        try? await request(path: "/calls/\(id)")
    }

    // ── Live calls ───────────────────────────────────────────

    func fetchLive() async {
        do {
            let resp: CallsResponse = try await request(path: "/calls/live")
            liveCalls = resp.calls
        } catch {}
    }

    func startLivePolling() {
        liveTimer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.fetchLive() }
            }
    }

    func stopLivePolling() {
        liveTimer?.cancel()
        liveTimer = nil
    }

    // ── Stats ────────────────────────────────────────────────

    func fetchStats() async {
        do {
            stats = try await request(path: "/calls/stats")
        } catch {}
    }

    func startStatsPolling() {
        statsTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.fetchStats() }
            }
    }

    // ── Scheduled calls ──────────────────────────────────────

    func fetchScheduled() async {
        do {
            let resp: ScheduledCallsResponse = try await request(path: "/calls/scheduled")
            scheduled = resp.scheduled
        } catch {
            lastError = error.localizedDescription
        }
    }

    func scheduleCall(
        to: String,
        goal: String,
        systemPrompt: String?,
        firstMessage: String?,
        scheduledAt: Date,
        notes: String
    ) async throws {
        let iso = ISO8601DateFormatter().string(from: scheduledAt)
        var body: [String: Any] = [
            "to":          to,
            "goal":        goal,
            "scheduledAt": iso,
            "notes":       notes,
        ]
        if let sp = systemPrompt, !sp.isEmpty { body["systemPrompt"] = sp }
        if let fm = firstMessage, !fm.isEmpty { body["firstMessage"] = fm }

        struct Response: Decodable { let ok: Bool }
        let _: Response = try await request(path: "/calls/schedule", method: "POST", body: body)
        await fetchScheduled()
    }

    func deleteScheduled(id: String) async throws {
        struct R: Decodable { let ok: Bool }
        let _: R = try await request(path: "/calls/schedule/\(id)", method: "DELETE")
        scheduled.removeAll { $0.id == id }
    }

    // ── Place immediate call ──────────────────────────────────

    func placeCall(to: String, goal: String, systemPrompt: String? = nil) async throws {
        var body: [String: Any] = ["to": to, "goal": goal]
        if let sp = systemPrompt { body["systemPrompt"] = sp }
        struct R: Decodable { let ok: Bool; let callId: String? }
        let _: R = try await request(path: "/calls/place", method: "POST", body: body)
        await fetchLive()
    }
}

// AnyCodable is defined in Conversation.swift
