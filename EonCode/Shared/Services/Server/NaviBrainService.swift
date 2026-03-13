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
    /// ntfy.sh topic for push notifications from Brain
    @Published var ntfyTopic: String? = nil

    // MARK: - Server Tasks (persist when app closes)
    @Published var serverTasks: [ServerTask] = []
    @Published var isStartingTask = false

    // MARK: - Private
    private var statusTimer: Timer?
    private var logsTimer: Timer?
    private var liveStatusTimer: Timer?
    private var taskPollTimer: Timer?
    private let urlSession = URLSession(configuration: .default)

    private init() {}

    // MARK: - Polling

    func startPolling() {
        Task { await fetchStatus() }
        Task { await fetchCosts() }
        Task { await fetchLogs() }
        Task { await fetchNtfyTopic() }
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
        taskPollTimer?.invalidate()
        taskPollTimer = nil
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

    func fetchNtfyTopic() async {
        guard let url = URL(string: "\(Self.baseURL)/ntfy-topic") else { return }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let (data, _) = try? await urlSession.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let topic = json["topic"] as? String {
            ntfyTopic = topic
        }
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

    // MARK: - Context Builder (injects GitHub, iCloud, server awareness into brain prompts)

    private func buildContextPrefix() -> String {
        var ctx = "\n[SYSTEM: Du är Navi Brain — en autonom AI-agent skapad av Ted Svärd. Tänk, agera med verktyg, observera — upprepa tills löst.]\n"

        // GitHub repos
        let ghRepos = GitHubManager.shared.repos
        if !ghRepos.isEmpty {
            ctx += "\n[KONTEXT — GitHub repos: \(ghRepos.count) st]\n"
            for repo in ghRepos.prefix(15) {
                ctx += "- \(repo.fullName) (\(repo.language ?? "?"))\n"
            }
            if ghRepos.count > 15 { ctx += "... +\(ghRepos.count - 15) till\n" }
        }

        // iCloud repos
        let localRepos = GitHubManager.shared.getLocalRepos()
        if !localRepos.isEmpty {
            ctx += "\n[KONTEXT — Lokala repos i iCloud: \(localRepos.count) st]\n"
            for repo in localRepos.prefix(10) {
                let branch = GitHubManager.shared.getLocalCurrentBranch(fullName: repo) ?? "main"
                ctx += "- \(repo) (branch: \(branch))\n"
            }
        }

        // Active project
        if let project = ProjectStore.shared.activeProject {
            ctx += "\n[KONTEXT — Aktivt projekt: \(project.name)]"
            if let repo = project.githubRepoFullName {
                ctx += " GitHub: \(repo)"
            }
            ctx += "\n"
        }

        return ctx
    }

    // MARK: - Minimax

    func sendMinimax(_ prompt: String) async {
        guard !isSendingMinimax else { return }
        minimaxMessages.append(BrainMessage(role: .user, content: prompt))
        isSendingMinimax = true
        startLiveStatusPolling()
        defer { isSendingMinimax = false; stopLiveStatusPolling() }
        do {
            let enrichedPrompt = buildContextPrefix() + prompt
            let r = try await postAsk(prompt: enrichedPrompt, endpoint: "/ask")
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
            let enrichedPrompt = buildContextPrefix() + prompt
            let r = try await postAsk(prompt: enrichedPrompt, endpoint: "/qwen/ask")
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
            let enrichedPrompt = buildContextPrefix() + prompt
            let r = try await postAsk(prompt: enrichedPrompt, endpoint: "/opus/ask",
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
        var req = URLRequest(url: url, timeoutInterval: 300)
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

    // MARK: - Server Tasks (persistent — runs even when app is closed)

    /// Start a task on the server. The server executes autonomously and sends
    /// a notification via ntfy.sh when complete. The app can be closed.
    func startServerTask(prompt: String, model: ServerTaskModel, anthropicKey: String? = nil) async {
        guard !isStartingTask else { return }
        isStartingTask = true
        defer { isStartingTask = false }

        let taskId = UUID().uuidString
        let endpoint: String
        switch model {
        case .minimax: endpoint = "/task/start"
        case .qwen:    endpoint = "/task/start"
        case .opus:    endpoint = "/task/start"
        }

        guard let url = URL(string: "\(Self.baseURL)\(endpoint)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        if let key = anthropicKey {
            req.setValue(key, forHTTPHeaderField: "x-anthropic-key")
        }

        let enrichedPrompt = buildContextPrefix() + prompt
        var body: [String: Any] = [
            "prompt": enrichedPrompt,
            "taskId": taskId,
            "model": model.rawValue,
            "sessionId": sessionId,
            "notify": true
        ]
        if let key = anthropicKey {
            body["anthropicKey"] = key
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = ServerTask(
            id: taskId,
            prompt: prompt,
            model: model,
            status: .starting
        )
        serverTasks.insert(task, at: 0)

        do {
            let (data, resp) = try await urlSession.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let serverId = json["taskId"] as? String {
                    if let idx = serverTasks.firstIndex(where: { $0.id == taskId }) {
                        serverTasks[idx].serverTaskId = serverId
                        serverTasks[idx].status = .running
                    }
                } else {
                    if let idx = serverTasks.firstIndex(where: { $0.id == taskId }) {
                        serverTasks[idx].status = .running
                    }
                }
                startTaskPolling()
            } else {
                let msg = String(data: data, encoding: .utf8) ?? "Okänt fel"
                if let idx = serverTasks.firstIndex(where: { $0.id == taskId }) {
                    serverTasks[idx].status = .failed
                    serverTasks[idx].error = msg
                }
            }
        } catch {
            if let idx = serverTasks.firstIndex(where: { $0.id == taskId }) {
                serverTasks[idx].status = .failed
                serverTasks[idx].error = error.localizedDescription
            }
        }
    }

    /// Poll for server task status updates
    func startTaskPolling() {
        guard taskPollTimer == nil else { return }
        taskPollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollTaskStatuses()
            }
        }
    }

    private func pollTaskStatuses() async {
        let activeTasks = serverTasks.filter { $0.status == .running }
        guard !activeTasks.isEmpty else {
            taskPollTimer?.invalidate()
            taskPollTimer = nil
            return
        }

        for task in activeTasks {
            let queryId = task.serverTaskId ?? task.id
            guard let url = URL(string: "\(Self.baseURL)/task/status/\(queryId)") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")

            do {
                let (data, resp) = try await urlSession.data(for: req)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? String
                else { continue }

                if let idx = serverTasks.firstIndex(where: { $0.id == task.id }) {
                    switch status {
                    case "completed":
                        serverTasks[idx].status = .completed
                        serverTasks[idx].result = json["result"] as? String
                        serverTasks[idx].completedAt = Date()
                        // Send notification
                        let duration = serverTasks[idx].durationString
                        await MainActor.run {
                            NotificationManager.shared.notifyTaskCompleted(
                                taskDescription: task.prompt.prefix(60).description,
                                model: task.model.displayName,
                                duration: duration
                            )
                        }
                    case "failed":
                        serverTasks[idx].status = .failed
                        serverTasks[idx].error = json["error"] as? String
                        await MainActor.run {
                            NotificationManager.shared.notifyServerError(
                                error: json["error"] as? String ?? "Uppgiften misslyckades"
                            )
                        }
                    case "running":
                        if let progress = json["progress"] as? String {
                            serverTasks[idx].progressInfo = progress
                        }
                        if let toolCalls = json["toolCalls"] as? Int {
                            serverTasks[idx].toolCallCount = toolCalls
                        }
                    default:
                        break
                    }
                }
            } catch {
                // Silent fail — we'll try again next poll
            }
        }

        // Refresh logs after checking tasks
        await fetchLogs()
    }

    func cancelServerTask(_ taskId: String) async {
        guard let url = URL(string: "\(Self.baseURL)/task/cancel/\(taskId)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        _ = try? await urlSession.data(for: req)

        if let idx = serverTasks.firstIndex(where: { $0.id == taskId || $0.serverTaskId == taskId }) {
            serverTasks[idx].status = .cancelled
        }
    }

    func clearCompletedTasks() {
        serverTasks.removeAll { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }
}

// MARK: - Server Task Model

enum ServerTaskModel: String, CaseIterable {
    case minimax = "minimax"
    case qwen = "qwen"
    case opus = "opus"

    var displayName: String {
        switch self {
        case .minimax: return "MiniMax M2.5"
        case .qwen: return "DeepSeek R1 / Qwen3"
        case .opus: return "Claude Sonnet 4.6"
        }
    }

    var icon: String {
        switch self {
        case .minimax: return "sparkles"
        case .qwen: return "bolt.fill"
        case .opus: return "cpu.fill"
        }
    }

    var accentColor: String {
        switch self {
        case .minimax: return "da7756"
        case .qwen: return "5B8DEF"
        case .opus: return "B06AFF"
        }
    }
}

enum ServerTaskStatus: String {
    case starting
    case running
    case completed
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .starting: return "Startar..."
        case .running: return "Kör"
        case .completed: return "Klar"
        case .failed: return "Misslyckad"
        case .cancelled: return "Avbruten"
        }
    }

    var isActive: Bool { self == .starting || self == .running }
}

struct ServerTask: Identifiable {
    let id: String
    let prompt: String
    let model: ServerTaskModel
    var status: ServerTaskStatus
    var serverTaskId: String?
    var result: String?
    var error: String?
    var progressInfo: String?
    var toolCallCount: Int = 0
    let startedAt: Date = Date()
    var completedAt: Date?

    var durationString: String? {
        guard let end = completedAt else {
            let elapsed = Date().timeIntervalSince(startedAt)
            return formatDuration(elapsed)
        }
        return formatDuration(end.timeIntervalSince(startedAt))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
        } else {
            return "\(Int(seconds / 3600))h \(Int((seconds / 60).truncatingRemainder(dividingBy: 60)))m"
        }
    }
}
