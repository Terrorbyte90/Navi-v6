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

// MARK: - ServerMessage
// Messages sent by Minimax (or other server-side agents) about autonomous runs,
// server health, scheduled actions, and status updates.

struct ServerMessage: Identifiable, Decodable {
    var id: String
    let timestamp: String?
    /// "info", "warn", "error", "autonomous_run", "health", "task_complete"
    let type: String?
    let title: String?
    let body: String
    let model: String?
    let project: String?

    var displayType: String { type ?? "info" }
    var displayTitle: String { title ?? "Meddelande" }
    var displayModel: String { model ?? "server" }
    var displayProject: String { project ?? "" }

    var typeIcon: String {
        switch (type ?? "info") {
        case "error":         return "exclamationmark.circle.fill"
        case "warn":          return "exclamationmark.triangle.fill"
        case "autonomous_run": return "play.circle.fill"
        case "health":        return "heart.fill"
        case "task_complete": return "checkmark.circle.fill"
        default:              return "info.circle.fill"
        }
    }

    var typeColor: String {
        switch (type ?? "info") {
        case "error":         return "error"
        case "warn":          return "warning"
        case "autonomous_run": return "minimax"
        case "health":        return "qwen"
        case "task_complete": return "opus"
        default:              return "default"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, type, title, body, model, project
    }
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

// MARK: - BrainSessionMode

enum BrainSessionMode: String, CaseIterable {
    case minimax, qwen, opus

    var displayName: String {
        switch self {
        case .minimax: return "MiniMax M2.5"
        case .qwen:    return "MiMo-V2 / Devstral / Llama"
        case .opus:    return "Claude Sonnet 4.6"
        }
    }

    var endpoint: String {
        switch self {
        case .minimax: return "/ask"
        case .qwen:    return "/qwen/ask"
        case .opus:    return "/opus/ask"
        }
    }

    /// Ordered fallback OpenRouter model IDs tried when the primary endpoint fails.
    /// Passed as `model` in the request body so the server can override its default.
    var fallbackModelChain: [(endpoint: String, modelId: String, label: String)] {
        switch self {
        case .minimax:
            return [] // MiniMax has its own API, no OpenRouter fallback
        case .qwen:
            return [
                ("/qwen/ask", "xiaomi/mimo-v2-flash:free",                  "MiMo-V2-Flash"),
                ("/qwen/ask", "mistralai/devstral-2512:free",               "Devstral-2512"),
                ("/qwen/ask", "meta-llama/llama-3.3-70b-instruct:free",     "Llama 3.3 70B"),
            ]
        case .opus:
            return [] // Opus uses Anthropic directly, no OpenRouter fallback
        }
    }

    var clearEndpoint: String {
        switch self {
        case .minimax: return "/minimax/history/clear"
        case .qwen:    return "/qwen/history/clear"
        case .opus:    return "/opus/history/clear"
        }
    }

    var icon: String {
        switch self {
        case .minimax: return "sparkles"
        case .qwen:    return "bolt.fill"
        case .opus:    return "cpu.fill"
        }
    }

    var accentHex: String {
        switch self {
        case .minimax: return "da7756"
        case .qwen:    return "5B8DEF"
        case .opus:    return "B06AFF"
        }
    }
}

// MARK: - BrainSession (one concurrent chat session per model)

@MainActor
final class BrainSession: ObservableObject, Identifiable {
    let id = UUID()
    let mode: BrainSessionMode
    let sessionId: String
    @Published var name: String
    @Published var messages: [BrainMessage] = []
    @Published var isSending = false
    let createdAt = Date()

    init(mode: BrainSessionMode, index: Int) {
        self.mode = mode
        self.sessionId = "ios-\(mode.rawValue)-\(UUID().uuidString.prefix(8))"
        self.name = "Session \(index)"
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

    // MARK: - Brain Sessions (multiple concurrent per model)
    @Published var brainSessions: [BrainSession] = []
    @Published var isSendingMinimax = false
    @Published var isSendingQwen = false
    @Published var isSendingOpus = false
    @Published var opusCostUSD: Double = 0.0
    @Published var opusTokensTotal: Int = 0

    /// Backward-compatible message counts (used by sidebars)
    var minimaxMessages: [BrainMessage] {
        brainSessions.filter { $0.mode == .minimax }.flatMap { $0.messages }
    }
    var qwenMessages: [BrainMessage] {
        brainSessions.filter { $0.mode == .qwen }.flatMap { $0.messages }
    }

    // MARK: - Logs
    @Published var logs: [BrainLogEntry] = []
    @Published var isLoadingLogs = false

    // MARK: - Server Messages (Minimax sends updates about autonomous runs, health etc.)
    @Published var serverMessages: [ServerMessage] = []
    @Published var isLoadingMessages = false

    // MARK: - Live Status (real-time tool call progress)
    @Published var liveStatus: BrainLiveStatus?
    /// ntfy.sh topic for push notifications from Brain
    @Published var ntfyTopic: String? = nil

    // MARK: - Server Tasks (persist when app closes)
    @Published var serverTasks: [ServerTask] = []
    @Published var isStartingTask = false

    // MARK: - Sequential Task Queue (up to 100 prompts executed in order)
    @Published var pendingTaskQueue: [QueuedServerPrompt] = []
    @Published var isProcessingQueue = false

    // MARK: - Private
    private var statusTimer: Timer?
    private var logsTimer: Timer?
    private var messagesTimer: Timer?
    private var liveStatusTimer: Timer?
    private var taskPollTimer: Timer?
    private let urlSession = URLSession(configuration: .default)

    private init() {}

    // MARK: - Polling

    func startPolling() {
        Task { await fetchStatus() }
        Task { await fetchCosts() }
        Task { await fetchLogs() }
        Task { await fetchServerMessages() }
        Task { await fetchNtfyTopic() }
        Task { await fetchPersistedTasks() }
        // Start ntfy push notification polling
        NotificationManager.shared.startNtfyPolling()
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
        // Fetch server messages every 30 seconds
        messagesTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchServerMessages()
            }
        }
    }

    func stopPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
        logsTimer?.invalidate()
        logsTimer = nil
        messagesTimer?.invalidate()
        messagesTimer = nil
        taskPollTimer?.invalidate()
        taskPollTimer = nil
        NotificationManager.shared.stopNtfyPolling()
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

    func fetchLogs(limit: Int = 100) async {
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

    /// Fetch server messages from the /messages endpoint (Minimax autonomous run reports, health alerts).
    /// Falls back gracefully if the endpoint doesn't exist yet.
    func fetchServerMessages() async {
        isLoadingMessages = true
        defer { isLoadingMessages = false }
        guard let url = URL(string: "\(Self.baseURL)/messages") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        guard let (data, resp) = try? await urlSession.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }

        // Try decoding as an array of ServerMessage
        if let messages = try? JSONDecoder().decode([ServerMessage].self, from: data) {
            // Merge: keep existing messages, add new ones
            let existingIDs = Set(serverMessages.map { $0.id })
            let newMessages = messages.filter { !existingIDs.contains($0.id) }
            serverMessages = (newMessages + serverMessages).prefix(200).map { $0 }
        } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msgs = json["messages"] as? [[String: Any]] {
            // Alternative: server wraps in { messages: [...] }
            let decoder = JSONDecoder()
            for msgDict in msgs {
                if let msgData = try? JSONSerialization.data(withJSONObject: msgDict),
                   let msg = try? decoder.decode(ServerMessage.self, from: msgData) {
                    if !serverMessages.contains(where: { $0.id == msg.id }) {
                        serverMessages.insert(msg, at: 0)
                    }
                }
            }
            // Trim to 200 messages
            if serverMessages.count > 200 { serverMessages = Array(serverMessages.prefix(200)) }
        }
    }

    /// Post a message from client to server /messages (e.g. user-generated notes)
    func postServerMessage(title: String, body: String, type: String = "info") async {
        guard let url = URL(string: "\(Self.baseURL)/messages") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let msgBody: [String: Any] = [
            "title": title,
            "body": body,
            "type": type,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "model": "client"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: msgBody)
        _ = try? await urlSession.data(for: req)
        // Refresh messages after posting
        Task { await fetchServerMessages() }
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
        let hasGitHubToken = !(KeychainManager.shared.githubToken?.isEmpty ?? true)

        var ctx = """

[SYSTEM — NAVI BRAIN]
Du är Navi Brain, en autonom AI-agent med fullständig verktygstillgång, skapad av Ted Svärd.

IDENTITET OCH KAPACITET:
- Du är en kraftfull autonom agent med verktyg för att läsa/skriva filer, köra kommandon, söka och modifiera GitHub-repos.
- Du har admin-tillgång till Ted Svärds GitHub (owner: Terrorbyte90) via API-token i x-github-token headern.
- Du KAN och SKA använda GitHub API direkt (https://api.github.com) med ditt token — aldrig säg att du saknar åtkomst.

GITHUB-TILLGÅNG:
- Token finns i x-github-token request-headern.
- Använd alltid "Authorization: token <värdet från x-github-token>" i GitHub API-anrop.
- Du har full admin-rätt: läsa repos, skapa/redigera filer, committa, skapa PRs, hantera issues, skapa branches mm.
- GitHub-ägare: Terrorbyte90

REACT-LOOP (obligatorisk arbetsmetod):
1. RESONERA — Analysera uppgiften. Identifiera vilka steg och verktyg som behövs.
2. AGERA — Anropa ett verktyg för att utföra nästa konkreta steg.
3. OBSERVERA — Läs verktygssvarets output noggrant.
4. UPPREPA — Fortsätt med nästa steg baserat på observationen.
5. SLUTFÖR — Ge ett fullständigt svar när uppgiften är löst.

VIKTIGA REGLER:
- Fortsätt loopen tills uppgiften är helt löst (upp till 50 iterationer).
- Säg ALDRIG att du saknar tillgång till GitHub, filer eller internet — du har det.
- Om ett verktyg misslyckas: analysera felet och försök med en annan strategi.
- Leverera alltid ett konkret resultat — inte bara en plan eller förklaring.
- Svara på svenska om inget annat begärs.
[/SYSTEM]

"""

        // GitHub token status
        if hasGitHubToken {
            ctx += "\n[GITHUB: Token tillgängligt i x-github-token header — du har admin-åtkomst till Terrorbyte90]\n"
        }

        // GitHub repos
        let ghRepos = GitHubManager.shared.repos
        if !ghRepos.isEmpty {
            ctx += "\n[KONTEXT — GitHub repos (\(ghRepos.count) st)]\n"
            for repo in ghRepos.prefix(15) {
                ctx += "- \(repo.fullName) (\(repo.language ?? "?"))\n"
            }
            if ghRepos.count > 15 { ctx += "... +\(ghRepos.count - 15) till\n" }
        }

        // iCloud repos
        let localRepos = GitHubManager.shared.getLocalRepos()
        if !localRepos.isEmpty {
            ctx += "\n[KONTEXT — Lokala repos i iCloud (\(localRepos.count) st)]\n"
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

    // MARK: - Brain Session Management

    func sessionsFor(_ mode: BrainSessionMode) -> [BrainSession] {
        brainSessions.filter { $0.mode == mode }
    }

    @discardableResult
    func createBrainSession(mode: BrainSessionMode) -> BrainSession {
        let index = sessionsFor(mode).count + 1
        let session = BrainSession(mode: mode, index: index)
        brainSessions.append(session)
        return session
    }

    func removeBrainSession(_ id: UUID) {
        brainSessions.removeAll { $0.id == id }
        syncSendingFlags()
    }

    /// Send a prompt to a specific session — multiple sessions can run in parallel
    func sendToSession(_ session: BrainSession, prompt: String, anthropicKey: String? = nil) async {
        guard !session.isSending else { return }
        session.messages.append(BrainMessage(role: .user, content: prompt))
        session.isSending = true
        syncSendingFlags()
        startLiveStatusPolling()
        defer {
            session.isSending = false
            syncSendingFlags()
            if !isAnySending { stopLiveStatusPolling() }
        }

        var extraHeaders: [String: String] = [:]
        if session.mode == .opus, let key = anthropicKey {
            extraHeaders["x-anthropic-key"] = key
        }

        let enrichedPrompt = buildContextPrefix() + prompt
        do {
            let r = try await postAskWithRetry(prompt: enrichedPrompt,
                                               endpoint: session.mode.endpoint,
                                               sessionId: session.sessionId,
                                               extraHeaders: extraHeaders)
            session.messages.append(BrainMessage(role: .assistant, content: r.response,
                                                 model: r.model, tokens: r.tokens, cost: r.cost,
                                                 toolCalls: r.toolCalls))
            if session.mode == .opus, let c = r.cost { opusCostUSD += c }
            let costStr = r.cost.map { String(format: "$%.4f", $0) }
            NotificationManager.shared.notifyTaskCompleted(
                taskDescription: prompt.prefix(60).description,
                model: session.mode == .opus
                    ? "Claude Sonnet 4.6\(costStr.map { " (\($0))" } ?? "")"
                    : session.mode.displayName,
                duration: nil
            )
        } catch {
            // Primary endpoint failed — try fallback model chain (qwen only)
            let chain = session.mode.fallbackModelChain
            var succeeded = false
            for (fbEndpoint, fbModelId, fbLabel) in chain {
                do {
                    var fbHeaders = extraHeaders
                    fbHeaders["x-model-override"] = fbModelId
                    let fbBody: [String: Any] = ["prompt": enrichedPrompt,
                                                  "sessionId": session.sessionId,
                                                  "model": fbModelId]
                    let r = try await postAskRaw(body: fbBody,
                                                 endpoint: fbEndpoint,
                                                 extraHeaders: fbHeaders)
                    session.messages.append(BrainMessage(
                        role: .assistant,
                        content: r.response,
                        model: fbLabel,
                        tokens: r.tokens,
                        cost: r.cost,
                        toolCalls: r.toolCalls
                    ))
                    succeeded = true
                    NotificationManager.shared.notifyTaskCompleted(
                        taskDescription: prompt.prefix(60).description,
                        model: fbLabel,
                        duration: nil
                    )
                    break
                } catch {
                    // Try next fallback
                    continue
                }
            }
            if !succeeded {
                session.messages.append(BrainMessage(role: .assistant,
                                                     content: "Fel: \(error.localizedDescription)"))
                NotificationManager.shared.notifyServerError(
                    error: "\(session.mode.displayName): \(error.localizedDescription)")
            }
        }
        Task { await fetchLogs() }
        if session.mode == .opus { Task { await fetchCosts() } }
    }

    func clearSession(_ session: BrainSession) {
        session.messages = []
        let sid = session.sessionId
        let endpoint = session.mode.clearEndpoint
        Task { _ = try? await postClear(endpoint: endpoint, sessionId: sid) }
    }

    /// Sync service-level sending flags from session states
    private func syncSendingFlags() {
        isSendingMinimax = brainSessions.contains { $0.mode == .minimax && $0.isSending }
        isSendingQwen    = brainSessions.contains { $0.mode == .qwen && $0.isSending }
        isSendingOpus    = brainSessions.contains { $0.mode == .opus && $0.isSending }
    }

    // MARK: - Fetch persisted tasks from server (syncs on startup)

    func fetchPersistedTasks() async {
        guard let url = URL(string: "\(Self.baseURL)/tasks") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        do {
            let (data, resp) = try await urlSession.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tasks = json["tasks"] as? [[String: Any]] {
                for taskJson in tasks {
                    guard let taskId = taskJson["taskId"] as? String,
                          let statusStr = taskJson["status"] as? String
                    else { continue }
                    // Only add tasks we don't already track locally
                    if serverTasks.contains(where: { $0.id == taskId || $0.serverTaskId == taskId }) { continue }
                    let modelStr = taskJson["model"] as? String ?? "minimax"
                    let model: ServerTaskModel = modelStr == "opus" ? .opus : modelStr == "qwen" ? .qwen : .minimax
                    let status: ServerTaskStatus
                    switch statusStr {
                    case "completed": status = .completed
                    case "failed": status = .failed
                    case "cancelled": status = .cancelled
                    case "running": status = .running
                    default: status = .running
                    }
                    var task = ServerTask(
                        id: taskId,
                        prompt: taskJson["prompt"] as? String ?? "",
                        model: model,
                        status: status
                    )
                    task.serverTaskId = taskId
                    task.result = taskJson["result"] as? String
                    task.error = taskJson["error"] as? String
                    if let tc = taskJson["toolCalls"] as? Int { task.toolCallCount = tc }
                    serverTasks.append(task)
                }
            }
        } catch {
            // Silent fail — best effort sync
        }
        // Start polling if there are active tasks
        if serverTasks.contains(where: { $0.status.isActive }) {
            startTaskPolling()
        }
    }

    // MARK: - HTTP Helpers

    /// Post with automatic retry (1 retry on timeout/network error)
    private func postAskWithRetry(prompt: String,
                                  endpoint: String,
                                  sessionId: String? = nil,
                                  extraHeaders: [String: String] = [:],
                                  maxRetries: Int = 1) async throws -> BrainAskResponse {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                return try await postAsk(prompt: prompt, endpoint: endpoint,
                                         sessionId: sessionId, extraHeaders: extraHeaders)
            } catch {
                lastError = error
                let nsError = error as NSError
                // Only retry on network/timeout errors, not HTTP 4xx/5xx
                let isRetryable = nsError.domain == NSURLErrorDomain &&
                    [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet].contains(nsError.code)
                if !isRetryable || attempt >= maxRetries { throw error }
                // Wait before retry
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private func postAsk(prompt: String,
                         endpoint: String,
                         sessionId sid: String? = nil,
                         extraHeaders: [String: String] = [:]) async throws -> BrainAskResponse {
        guard let url = URL(string: "\(Self.baseURL)\(endpoint)") else { throw URLError(.badURL) }
        let effectiveSessionId = sid ?? sessionId
        var req = URLRequest(url: url, timeoutInterval: 300)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(effectiveSessionId, forHTTPHeaderField: "x-session-id")
        // Send GitHub token so server models have admin GitHub access
        if let githubToken = KeychainManager.shared.githubToken, !githubToken.isEmpty {
            req.setValue(githubToken, forHTTPHeaderField: "x-github-token")
        }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }

        let body: [String: Any] = ["prompt": prompt, "sessionId": effectiveSessionId]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await urlSession.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "NaviBrain", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(BrainAskResponse.self, from: data)
    }

    /// Post with a fully custom body dict — used by fallback model chain
    private func postAskRaw(body: [String: Any],
                             endpoint: String,
                             extraHeaders: [String: String] = [:]) async throws -> BrainAskResponse {
        guard let url = URL(string: "\(Self.baseURL)\(endpoint)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 300)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await urlSession.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "NaviBrain", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(BrainAskResponse.self, from: data)
    }

    private func postClear(endpoint: String, sessionId sid: String? = nil) async throws {
        guard let url = URL(string: "\(Self.baseURL)\(endpoint)") else { return }
        let effectiveSessionId = sid ?? sessionId
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(effectiveSessionId, forHTTPHeaderField: "x-session-id")
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
        if let githubToken = KeychainManager.shared.githubToken, !githubToken.isEmpty {
            req.setValue(githubToken, forHTTPHeaderField: "x-github-token")
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
                            // Kick off next queued prompt (if any)
                            Task { await self.processNextQueued() }
                        }
                    case "failed":
                        serverTasks[idx].status = .failed
                        serverTasks[idx].error = json["error"] as? String
                        await MainActor.run {
                            NotificationManager.shared.notifyServerError(
                                error: json["error"] as? String ?? "Uppgiften misslyckades"
                            )
                            // Also advance queue on failure so we don't block
                            Task { await self.processNextQueued() }
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

    // MARK: - GitHub → Server Sync

    /// Tell the server to pull the latest changes for all known repos.
    /// Runs a git pull on each cloned repo on the server side.
    func triggerServerGitSync() async {
        guard isConnected else { return }
        // Build a shell command that pulls all repos found in /root (up to 20)
        let repoNames = GitHubManager.shared.repos.prefix(20).map { $0.name }
        guard !repoNames.isEmpty else { return }
        let pullCmds = repoNames
            .map { "git -C /root/repos/\($0) pull --ff-only 2>/dev/null || true" }
            .joined(separator: " && ")
        let cmd = "(\(pullCmds)) && echo 'NAVI_GIT_SYNC_OK'"
        guard let url = URL(string: "\(Self.baseURL)/exec") else { return }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["cmd": cmd])
        _ = try? await urlSession.data(for: req)
        NaviLog.info("NaviBrainService: GitHub→Server git sync triggered")
    }

    func clearCompletedTasks() {
        serverTasks.removeAll { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }

    /// Remove a single task by ID (for swipe-to-delete / dismiss button in UI)
    func dismissTask(_ id: String) {
        serverTasks.removeAll { $0.id == id }
    }

    // MARK: - Sequential Prompt Queue

    /// Add multiple prompts to the sequential queue and start processing.
    func enqueuePrompts(_ prompts: [String], model: ServerTaskModel, anthropicKey: String? = nil) {
        let items = prompts.map { QueuedServerPrompt(prompt: $0, model: model, anthropicKey: anthropicKey) }
        pendingTaskQueue.append(contentsOf: items)
        Task { await processNextQueued() }
    }

    func removeQueuedPrompt(_ id: UUID) {
        pendingTaskQueue.removeAll { $0.id == id }
    }

    func clearPendingQueue() {
        pendingTaskQueue.removeAll()
    }

    /// Called whenever a task finishes — kicks off the next queued prompt.
    func processNextQueued() async {
        guard !pendingTaskQueue.isEmpty else { isProcessingQueue = false; return }
        let hasActive = serverTasks.contains { $0.status.isActive }
        guard !hasActive else { return } // Wait for running task before starting next
        isProcessingQueue = true
        let next = pendingTaskQueue.removeFirst()
        await startServerTask(prompt: next.prompt, model: next.model, anthropicKey: next.anthropicKey)
        // Note: after startServerTask the server-side task runs async — processNextQueued is
        // called again from pollTaskStatuses when the task completes.
    }
}

// MARK: - Queued Server Prompt (lightweight input for the sequential queue)

struct QueuedServerPrompt: Identifiable {
    let id = UUID()
    let prompt: String
    let model: ServerTaskModel
    let anthropicKey: String?
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
