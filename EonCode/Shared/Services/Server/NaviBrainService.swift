import Foundation
import Combine

// MARK: - Models

struct BrainLiveStatus: Decodable {
    let active: Bool
    let model: String?
    let tool: String?
    let iter: Int?
}

struct BrainServerStatus: Decodable {
    let status: String
    let version: String?
    let repos: Int?
    let model: String?
    var isOnline: Bool { status == "online" }
}

struct BrainExecResponse: Decodable {
    let output: String?
    let stdout: String?
    let stderr: String?
    let error: String?

    var combinedOutput: String {
        var parts: [String] = []
        if let o = output, !o.isEmpty   { parts.append(o) }
        if let o = stdout, !o.isEmpty   { parts.append(o) }
        if let e = stderr, !e.isEmpty   { parts.append("⚠ \(e)") }
        if let e = error,  !e.isEmpty   { parts.append("✗ \(e)") }
        return parts.joined(separator: "\n")
    }

    enum CodingKeys: String, CodingKey {
        case output, stdout, stderr, error
    }
}

struct BrainAskResponse: Decodable {
    let response: String
    let tokens: Int?
    let model: String?
    let cost: Double?
    let sessionId: String?
    let toolCalls: [String]?
}

struct BrainCostsResponse: Decodable {
    let totalCost: Double?
    let totalRequests: Int?

    enum CodingKeys: String, CodingKey {
        case totalCost     = "total_cost"
        case totalRequests = "total_requests"
    }
}

struct BrainLogEntry: Identifiable, Decodable {
    let id = UUID()
    let timestamp: String?
    let action: String?
    let details: String?
    let project: String?
    let tokens: Int?
    let raw: String?

    var displayAction: String { action ?? "LOG" }
    var displayDetails: String { details ?? raw ?? "" }
    var displayProject: String { project ?? "system" }

    var actionColor: String {
        switch action?.uppercased() ?? "" {
        case "ERROR":          return "error"
        case "OPUS_CHAT", "OPUS": return "opus"
        case "MINIMAX", "BRAIN": return "minimax"
        case "QWEN":           return "qwen"
        case "WARN":           return "warning"
        default:               return "default"
        }
    }

    enum CodingKeys: String, CodingKey {
        case timestamp, action, details, project, tokens, raw
    }
}

struct BrainLogsResponse: Decodable {
    let logs: [BrainLogEntry]
    let total: Int?
}

struct BrainMessage: Identifiable {
    let id    = UUID()
    let role: BrainRole
    let content: String
    let model: String?
    let tokens: Int?
    let cost: Double?
    let timestamp: Date
    /// Tool calls executed by the model before producing this response
    let toolCalls: [String]?

    enum BrainRole { case user, assistant }

    init(role: BrainRole, content: String, model: String? = nil,
         tokens: Int? = nil, cost: Double? = nil, toolCalls: [String]? = nil) {
        self.role      = role
        self.content   = content
        self.model     = model
        self.tokens    = tokens
        self.cost      = cost
        self.toolCalls = toolCalls
        self.timestamp = Date()
    }
}

struct TerminalLine: Identifiable {
    let id        = UUID()
    enum LineType { case command, output, error, info }
    let type: LineType
    let text: String
}

// MARK: - NaviBrainService

@MainActor
final class NaviBrainService: ObservableObject {
    static let shared = NaviBrainService()

    // MARK: - Config
    static let baseURL    = "http://209.38.98.107:3001"
    private let apiKey    = "navi-brain-2026"
    private let sessionId = "ios-\(Int(Date().timeIntervalSince1970) % 100000)"

    // MARK: - Connection
    @Published var isConnected    = false
    @Published var serverStatus: BrainServerStatus?
    @Published var serverCosts: BrainCostsResponse?

    // MARK: - Terminal
    @Published var terminalLines: [TerminalLine] = []
    @Published var isTerminalSending = false

    // MARK: - Minimax
    @Published var minimaxMessages: [BrainMessage] = []
    @Published var isSendingMinimax = false

    // MARK: - Qwen
    @Published var qwenMessages: [BrainMessage] = []
    @Published var isSendingQwen = false

    // MARK: - Opus-Brain
    @Published var opusMessages: [BrainMessage] = []
    @Published var isSendingOpus = false
    @Published var opusCostUSD: Double = 0.0   // running total from server
    @Published var opusTokensTotal: Int = 0

    // MARK: - Logs
    @Published var logs: [BrainLogEntry] = []
    @Published var isLoadingLogs = false

    // MARK: - Live Status (real-time tool call progress)
    @Published var liveStatus: BrainLiveStatus?

    // MARK: - Private
    private var statusTimer: Timer?
    private var logsTimer: Timer?
    private var liveStatusTimer: Timer?
    private let urlSession = URLSession(configuration: .default)

    private init() {}

    // MARK: - Polling

    func startPolling() {
        Task { await fetchStatus() }
        Task { await fetchCosts() }
        Task { await fetchLogs() }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchStatus()
            }
        }
        logsTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchLogs()
            }
        }
    }

    func stopPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
        logsTimer?.invalidate()
        logsTimer = nil
    }

    // MARK: - Live Status Polling (while any model is sending)

    private func startLiveStatusPolling() {
        guard liveStatusTimer == nil else { return }
        liveStatusTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchLiveStatus()
            }
        }
    }

    private func stopLiveStatusPolling() {
        liveStatusTimer?.invalidate()
        liveStatusTimer = nil
        liveStatus = nil
    }

    private var isAnySending: Bool {
        isSendingMinimax || isSendingQwen || isSendingOpus
    }

    func fetchLiveStatus() async {
        guard let url = URL(string: "\(Self.baseURL)/brain/live-status") else { return }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let (data, _) = try? await urlSession.data(for: req) {
            liveStatus = try? JSONDecoder().decode(BrainLiveStatus.self, from: data)
        }
        // Stop polling when no model is working
        if !isAnySending {
            stopLiveStatusPolling()
        }
    }

    func fetchStatus() async {
        guard let url = URL(string: "\(Self.baseURL)/") else { return }
        do {
            let (data, resp) = try await urlSession.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let status = try? JSONDecoder().decode(BrainServerStatus.self, from: data) {
                serverStatus = status
                isConnected  = status.isOnline
            } else {
                isConnected = false
            }
        } catch {
            isConnected = false
        }
    }

    func fetchCosts() async {
        guard let url = URL(string: "\(Self.baseURL)/costs") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let (data, _) = try? await urlSession.data(for: req) {
            serverCosts = try? JSONDecoder().decode(BrainCostsResponse.self, from: data)
        }

        // Also fetch Opus cost
        guard let opusURL = URL(string: "\(Self.baseURL)/opus/status") else { return }
        var opusReq = URLRequest(url: opusURL, timeoutInterval: 10)
        opusReq.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let (data, _) = try? await urlSession.data(for: opusReq),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            opusCostUSD    = json["totalCost"] as? Double ?? opusCostUSD
            opusTokensTotal = json["totalTokens"] as? Int ?? opusTokensTotal
        }
    }

    func fetchLogs(limit: Int = 30) async {
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        guard let url = URL(string: "\(Self.baseURL)/logs?limit=\(limit)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let (data, _) = try? await urlSession.data(for: req),
           let resp = try? JSONDecoder().decode(BrainLogsResponse.self, from: data) {
            logs = resp.logs
        }
    }

    // MARK: - Terminal (HTTP /exec)

    func execCommand(_ command: String) async {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        terminalLines.append(TerminalLine(type: .command, text: cmd))
        isTerminalSending = true
        defer { isTerminalSending = false }

        guard let url = URL(string: "\(Self.baseURL)/exec") else {
            terminalLines.append(TerminalLine(type: .error, text: "Ogiltig URL"))
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["cmd": cmd])

        do {
            let (data, _) = try await urlSession.data(for: req)
            if let exec = try? JSONDecoder().decode(BrainExecResponse.self, from: data) {
                let out = exec.combinedOutput
                terminalLines.append(TerminalLine(
                    type: out.isEmpty ? .info : .output,
                    text: out.isEmpty ? "(tom utdata)" : out
                ))
            } else if let raw = String(data: data, encoding: .utf8) {
                terminalLines.append(TerminalLine(type: .output, text: raw))
            }
        } catch {
            terminalLines.append(TerminalLine(type: .error, text: "Fel: \(error.localizedDescription)"))
        }

        // Refresh logs after exec
        Task { await fetchLogs() }
    }

    func clearTerminal() { terminalLines = [] }

    // MARK: - Minimax

    func sendMinimax(_ prompt: String) async {
        guard !isSendingMinimax else { return }
        minimaxMessages.append(BrainMessage(role: .user, content: prompt))
        isSendingMinimax = true
        startLiveStatusPolling()
        defer { isSendingMinimax = false; stopLiveStatusPolling() }
        do {
            let r = try await postAsk(prompt: prompt, endpoint: "/ask")
            minimaxMessages.append(BrainMessage(role: .assistant, content: r.response,
                                                model: r.model, tokens: r.tokens,
                                                toolCalls: r.toolCalls))
        } catch {
            minimaxMessages.append(BrainMessage(role: .assistant,
                                                content: "Fel: \(error.localizedDescription)"))
        }
        Task { await fetchLogs() }
    }

    func clearMinimaxHistory() {
        minimaxMessages = []
        Task { _ = try? await postClear(endpoint: "/minimax/history/clear") }
    }

    // MARK: - Qwen

    func sendQwen(_ prompt: String) async {
        guard !isSendingQwen else { return }
        qwenMessages.append(BrainMessage(role: .user, content: prompt))
        isSendingQwen = true
        startLiveStatusPolling()
        defer { isSendingQwen = false; stopLiveStatusPolling() }
        do {
            let r = try await postAsk(prompt: prompt, endpoint: "/qwen/ask")
            qwenMessages.append(BrainMessage(role: .assistant, content: r.response,
                                             model: r.model, tokens: r.tokens,
                                             toolCalls: r.toolCalls))
        } catch {
            qwenMessages.append(BrainMessage(role: .assistant,
                                             content: "Fel: \(error.localizedDescription)"))
        }
        Task { await fetchLogs() }
    }

    func clearQwenHistory() {
        qwenMessages = []
        Task { _ = try? await postClear(endpoint: "/qwen/history/clear") }
    }

    // MARK: - Opus-Brain (requires Anthropic key)

    func sendOpus(_ prompt: String, anthropicKey: String) async {
        guard !isSendingOpus else { return }
        opusMessages.append(BrainMessage(role: .user, content: prompt))
        isSendingOpus = true
        startLiveStatusPolling()
        defer { isSendingOpus = false; stopLiveStatusPolling() }
        do {
            let r = try await postAsk(prompt: prompt, endpoint: "/opus/ask",
                                      extraHeaders: ["x-anthropic-key": anthropicKey])
            opusMessages.append(BrainMessage(role: .assistant, content: r.response,
                                             model: r.model, tokens: r.tokens, cost: r.cost,
                                             toolCalls: r.toolCalls))
            // Update running cost
            if let c = r.cost { opusCostUSD += c }
        } catch {
            opusMessages.append(BrainMessage(role: .assistant,
                                             content: "Fel: \(error.localizedDescription)"))
        }
        Task {
            await fetchLogs()
            await fetchCosts()
        }
    }

    func clearOpusHistory() {
        opusMessages = []
        Task { _ = try? await postClear(endpoint: "/opus/history/clear") }
    }

    // MARK: - HTTP Helpers

    private func postAsk(prompt: String,
                         endpoint: String,
                         extraHeaders: [String: String] = [:]) async throws -> BrainAskResponse {
        guard let url = URL(string: "\(Self.baseURL)\(endpoint)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }

        let body: [String: Any] = ["prompt": prompt, "sessionId": sessionId]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await urlSession.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "NaviBrain", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(BrainAskResponse.self, from: data)
    }

    private func postClear(endpoint: String) async throws {
        guard let url = URL(string: "\(Self.baseURL)\(endpoint)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        _ = try await urlSession.data(for: req)
    }
}
