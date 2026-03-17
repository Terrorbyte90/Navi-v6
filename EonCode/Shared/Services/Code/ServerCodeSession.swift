import Foundation
import SwiftUI

// MARK: - Event types (mirrors server AG-UI protocol)

enum ServerEventType: String, Decodable {
    case connected    = "CONNECTED"
    case stateSnapshot = "STATE_SNAPSHOT"
    case runStarted   = "RUN_STARTED"
    case textDelta    = "TEXT_DELTA"
    case textCommit   = "TEXT_COMMIT"
    case toolStart    = "TOOL_START"
    case toolResult   = "TOOL_RESULT"
    case phase        = "PHASE"
    case todo         = "TODO"
    case gitCommit    = "GIT_COMMIT"
    case iteration    = "ITERATION"
    case runFinished  = "RUN_FINISHED"
    case runError     = "RUN_ERROR"
    case lintWarn     = "LINT_WARN"
    case compacting   = "COMPACTING"
    case ping         = "PING"
    case error        = "ERROR"
    case unknown
}

struct ServerEvent: Decodable {
    let type: ServerEventType
    let seq: Int?
    let ts: Double?

    // TEXT_DELTA / TEXT_COMMIT
    let delta: String?
    let text: String?

    // TOOL_START / TOOL_RESULT
    let toolId: String?
    let name: String?
    let params: AnyCodableDict?
    let result: String?
    let isError: Bool?
    let durationMs: Int?

    // PHASE
    let phase: String?
    let label: String?

    // TODO
    let todos: [ServerTodoItem]?

    // GIT_COMMIT
    let hash: String?
    let message: String?
    let filesChanged: String?
    let timestamp: String?

    // ITERATION
    let n: Int?
    let maxN: Int?

    // RUN_STARTED
    let task: String?
    let model: String?

    // RUN_FINISHED
    let summary: String?

    // LINT_WARN
    let path: String?
    let error: String?

    // CONNECTED
    let sessionId: String?
    let hasHistory: Bool?

    // STATE_SNAPSHOT
    let status: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case type, seq, ts, delta, text, toolId, name, params, result
        case isError, durationMs, phase, label, todos, hash, message
        case filesChanged, timestamp, n, maxN, task, model, summary
        case path, error, sessionId, hasHistory, status, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type         = (try? c.decode(ServerEventType.self, forKey: .type)) ?? .unknown
        seq          = try? c.decode(Int.self,    forKey: .seq)
        ts           = try? c.decode(Double.self, forKey: .ts)
        delta        = try? c.decode(String.self, forKey: .delta)
        text         = try? c.decode(String.self, forKey: .text)
        toolId       = try? c.decode(String.self, forKey: .toolId)
        name         = try? c.decode(String.self, forKey: .name)
        params       = try? c.decode(AnyCodableDict.self, forKey: .params)
        result       = try? c.decode(String.self, forKey: .result)
        isError      = try? c.decode(Bool.self,   forKey: .isError)
        durationMs   = try? c.decode(Int.self,    forKey: .durationMs)
        phase        = try? c.decode(String.self, forKey: .phase)
        label        = try? c.decode(String.self, forKey: .label)
        todos        = try? c.decode([ServerTodoItem].self, forKey: .todos)
        hash         = try? c.decode(String.self, forKey: .hash)
        message      = try? c.decode(String.self, forKey: .message)
        filesChanged = try? c.decode(String.self, forKey: .filesChanged)
        timestamp    = try? c.decode(String.self, forKey: .timestamp)
        n            = try? c.decode(Int.self,    forKey: .n)
        maxN         = try? c.decode(Int.self,    forKey: .maxN)
        task         = try? c.decode(String.self, forKey: .task)
        model        = try? c.decode(String.self, forKey: .model)
        summary      = try? c.decode(String.self, forKey: .summary)
        path         = try? c.decode(String.self, forKey: .path)
        error        = try? c.decode(String.self, forKey: .error)
        sessionId    = try? c.decode(String.self, forKey: .sessionId)
        hasHistory   = try? c.decode(Bool.self,   forKey: .hasHistory)
        status       = try? c.decode(String.self, forKey: .status)
        createdAt    = try? c.decode(String.self, forKey: .createdAt)
    }
}

// Simple wrapper for arbitrary JSON dict — converts all values to String
struct AnyCodableDict: Decodable {
    let dict: [String: String]

    private struct AnyStringValue: Decodable {
        let stringValue: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self)  { stringValue = s; return }
            if let i = try? c.decode(Int.self)      { stringValue = String(i); return }
            if let d = try? c.decode(Double.self)   { stringValue = String(d); return }
            if let b = try? c.decode(Bool.self)     { stringValue = String(b); return }
            stringValue = ""
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let raw = try? c.decode([String: AnyStringValue].self) {
            dict = raw.mapValues { $0.stringValue }
        } else {
            dict = [:]
        }
    }
}

// MARK: - Data models

struct ServerTodoItem: Identifiable, Decodable, Equatable {
    let id: String
    let title: String
    let done: Bool
}

struct ServerToolEvent: Identifiable {
    let id: String
    let toolId: String
    let name: String
    let params: [String: String]
    var result: String = ""
    var isError: Bool = false
    var isComplete: Bool = false
    var durationMs: Int = 0
    let startedAt = Date()

    var icon: String {
        switch name {
        case "read_file":      return "doc.text"
        case "write_file":     return "square.and.pencil"
        case "edit_file":      return "pencil.and.outline"
        case "run_command":    return "terminal"
        case "grep":           return "magnifyingglass"
        case "list_files":     return "folder"
        case "todo_write":     return "checklist"
        case "git_commit":     return "arrow.triangle.branch"
        case "web_search":     return "globe"
        case "fetch_url":      return "globe.americas"
        default:               return "wrench"
        }
    }
}

struct ServerGitCheckpoint: Identifiable {
    let id: String
    let hash: String
    let message: String
    let filesChanged: String
    let timestamp: String
}

enum ServerChatRole { case user, assistant }

struct ServerChatMessage: Identifiable {
    let id: UUID
    let role: ServerChatRole
    let text: String
    let toolEvents: [ServerToolEvent]
    let gitCheckpoint: ServerGitCheckpoint?
    let createdAt: Date
}

// MARK: - Connection state

enum ServerConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
}

// MARK: - ServerCodeSession

@MainActor
final class ServerCodeSession: ObservableObject {

    // MARK: Published state

    @Published var connectionState: ServerConnectionState = .disconnected
    @Published var sessionId: String?
    @Published var isRunning: Bool = false
    @Published var phase: String = "idle"
    @Published var phaseLabel: String = ""
    @Published var streamingText: String = ""
    @Published var messages: [ServerChatMessage] = []
    @Published var todos: [ServerTodoItem] = []
    @Published var toolEvents: [ServerToolEvent] = []
    @Published var liveToolName: String? = nil
    @Published var iteration: Int = 0
    @Published var maxIteration: Int = 40
    @Published var gitCheckpoints: [ServerGitCheckpoint] = []
    @Published var lintWarnings: [String] = []
    @Published var lastError: String?
    @Published var task: String = ""

    // MARK: Singleton
    static let shared = ServerCodeSession()
    private init() {
        // Load saved sessionId
        if let saved = UserDefaults.standard.string(forKey: "serverCodeSessionId") {
            sessionId = saved
        }
    }

    // MARK: Private

    private var wsTask: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1
    private var lastSeq: Int = 0
    private var isIntentionalStop = false
    private var accumulatedText: String = ""
    private var pendingToolEvents: [ServerToolEvent] = []

    private var serverURL: String {
        UserDefaults.standard.string(forKey: "naviServerURL") ?? "http://209.38.98.107:3001"
    }

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "naviServerAPIKey") ?? "navi-brain-2026"
    }

    private var openRouterKey: String {
        KeychainManager.shared.openRouterAPIKey ?? ""
    }

    private var anthropicAPIKey: String {
        KeychainManager.shared.anthropicAPIKey ?? ""
    }

    // MARK: - Public API

    func startNewSession(task: String, model: String) {
        isIntentionalStop = false
        self.task = task
        // Clear old state
        messages = []
        todos = []
        toolEvents = []
        gitCheckpoints = []
        lintWarnings = []
        streamingText = ""
        iteration = 0
        lastError = nil
        accumulatedText = ""
        pendingToolEvents = []
        sessionId = nil
        lastSeq = 0

        connectAndStart(task: task, model: model)
    }

    func resumeSession(_ id: String) {
        guard sessionId != id || connectionState == .disconnected else { return }
        sessionId = id
        lastSeq = 0
        connect(sessionId: id)
    }

    func stop() {
        isIntentionalStop = true
        sendMessage(["type": "STOP"])
    }

    func sendUserMessage(_ text: String) {
        guard connectionState == .connected, let _ = sessionId else { return }
        sendMessage(["type": "SEND", "text": text])
        // Add user message optimistically
        let msg = ServerChatMessage(id: UUID(), role: ServerChatRole.user, text: text, toolEvents: [], gitCheckpoint: nil, createdAt: Date())
        messages.append(msg)
    }

    func disconnect() {
        isIntentionalStop = true
        reconnectTask?.cancel()
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        connectionState = .disconnected
    }

    // MARK: - Connection

    private func connectAndStart(task: String, model: String) {
        let openrouterKey = openRouterKey
        let anthropicKey  = anthropicAPIKey

        connectionState = .connecting
        let wsURL = serverURL.replacingOccurrences(of: "http://", with: "ws://")
                             .replacingOccurrences(of: "https://", with: "wss://")
        guard let url = URL(string: "\(wsURL)/code/ws?key=\(apiKey)") else {
            connectionState = .disconnected
            lastError = "Invalid server URL"
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        wsTask = URLSession.shared.webSocketTask(with: req)
        wsTask?.resume()
        connectionState = .connected

        listenForMessages()

        // Send START
        var startMsg: [String: Any] = [
            "type": "START",
            "task": task,
            "model": model,
        ]
        if !openrouterKey.isEmpty { startMsg["openrouterKey"] = openrouterKey }
        if !anthropicKey.isEmpty  { startMsg["anthropicKey"]  = anthropicKey  }
        sendMessage(startMsg)
    }

    private func connect(sessionId: String) {
        connectionState = .connecting
        let wsURL = serverURL.replacingOccurrences(of: "http://", with: "ws://")
                             .replacingOccurrences(of: "https://", with: "wss://")
        guard let url = URL(string: "\(wsURL)/code/ws?key=\(apiKey)") else {
            connectionState = .disconnected
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        wsTask = URLSession.shared.webSocketTask(with: req)
        wsTask?.resume()
        connectionState = .connected

        listenForMessages()
        sendMessage(["type": "SUBSCRIBE", "sessionId": sessionId, "lastSeq": lastSeq])
    }

    private func listenForMessages() {
        wsTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let msg):
                    switch msg {
                    case .string(let text):
                        self.handleRawMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleRawMessage(text)
                        }
                    @unknown default: break
                    }
                    // Continue listening
                    self.listenForMessages()

                case .failure(let err):
                    self.connectionState = .disconnected
                    if !self.isIntentionalStop {
                        self.scheduleReconnect()
                    }
                    _ = err
                }
            }
        }
    }

    private func scheduleReconnect() {
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let sid = self.sessionId {
                    self.connectionState = .reconnecting(attempt: Int(self.reconnectDelay / 2))
                    self.connect(sessionId: sid)
                }
            }
        }
    }

    // MARK: - Send

    private func sendMessage(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        wsTask?.send(.string(text)) { _ in }
    }

    // MARK: - Event handling

    private func handleRawMessage(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let event = try? JSONDecoder().decode(ServerEvent.self, from: data)
        else { return }

        if let seq = event.seq {
            lastSeq = max(lastSeq, seq + 1)
        }

        handleEvent(event)
    }

    private func handleEvent(_ event: ServerEvent) {
        switch event.type {

        case .ping:
            sendMessage(["type": "PONG"])

        case .connected:
            connectionState = .connected
            reconnectDelay = 1
            if let sid = event.sessionId {
                sessionId = sid
                UserDefaults.standard.set(sid, forKey: "serverCodeSessionId")
            }

        case .stateSnapshot:
            if let status = event.status {
                isRunning = (status == "running")
                phase = status
            }
            if let t = event.task { task = t }
            // todos/gitCheckpoints come in their own events

        case .runStarted:
            isRunning = true
            phase = "running"
            phaseLabel = "Startar…"
            if let t = event.task { task = t }
            streamingText = ""
            toolEvents = []
            pendingToolEvents = []
            accumulatedText = ""

        case .textDelta:
            if let d = event.delta {
                streamingText += d
                accumulatedText += d
            }

        case .textCommit:
            let committed = event.text ?? accumulatedText
            if !committed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commitCurrentText(text: committed)
            }
            streamingText = ""
            accumulatedText = ""

        case .toolStart:
            let ev = ServerToolEvent(
                id: UUID().uuidString,
                toolId: event.toolId ?? UUID().uuidString,
                name: event.name ?? "tool",
                params: event.params?.dict ?? [:]
            )
            toolEvents.append(ev)
            pendingToolEvents.append(ev)
            liveToolName = event.name

        case .toolResult:
            let toolId = event.toolId ?? ""
            if let idx = toolEvents.lastIndex(where: { $0.toolId == toolId && !$0.isComplete }) {
                toolEvents[idx].result     = event.result ?? ""
                toolEvents[idx].isError    = event.isError ?? false
                toolEvents[idx].isComplete = true
                toolEvents[idx].durationMs = event.durationMs ?? 0
            }
            // Also update in pending
            if let idx = pendingToolEvents.lastIndex(where: { $0.toolId == toolId }) {
                pendingToolEvents[idx].result     = event.result ?? ""
                pendingToolEvents[idx].isError    = event.isError ?? false
                pendingToolEvents[idx].isComplete = true
            }
            liveToolName = nil

        case .phase:
            phase = event.phase ?? phase
            if let lbl = event.label { phaseLabel = lbl }
            if phase == "done" { liveToolName = nil }

        case .todo:
            if let items = event.todos { todos = items }

        case .gitCommit:
            let cp = ServerGitCheckpoint(
                id: UUID().uuidString,
                hash: event.hash ?? "???",
                message: event.message ?? "",
                filesChanged: event.filesChanged ?? "",
                timestamp: event.timestamp ?? ""
            )
            gitCheckpoints.append(cp)
            // Attach to current message context
            commitCurrentText(text: streamingText.isEmpty ? nil : streamingText, gitCheckpoint: cp)
            streamingText = ""
            accumulatedText = ""

        case .iteration:
            iteration    = event.n ?? iteration
            maxIteration = event.maxN ?? maxIteration

        case .lintWarn:
            if let p = event.path { lintWarnings.append(p) }

        case .compacting:
            phaseLabel = "Kompakterar kontext…"

        case .runFinished:
            isRunning = false
            phase = "done"
            phaseLabel = event.summary ?? "Klar"
            liveToolName = nil
            streamingText = ""
            // Final commit if any pending text
            if !accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commitCurrentText(text: accumulatedText)
                accumulatedText = ""
            }

        case .runError:
            isRunning = false
            phase = "error"
            lastError = event.error
            liveToolName = nil
            streamingText = ""

        case .error:
            lastError = event.error

        default:
            break
        }
    }

    // MARK: - Message committing

    private func commitCurrentText(text: String? = nil, gitCheckpoint: ServerGitCheckpoint? = nil) {
        let content = text ?? accumulatedText
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || gitCheckpoint != nil else { return }

        let msg = ServerChatMessage(
            id: UUID(),
            role: ServerChatRole.assistant,
            text: content,
            toolEvents: pendingToolEvents,
            gitCheckpoint: gitCheckpoint,
            createdAt: Date()
        )
        messages.append(msg)
        pendingToolEvents = []
    }
}
