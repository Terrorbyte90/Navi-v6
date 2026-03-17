import Foundation
import SwiftUI

// MARK: - CodeServerSession

struct CodeServerSession: Identifiable, Codable {
    let id: String
    var name: String
    var status: CodeServerStatus
    var model: String
    var messages: [CodeServerMessage]
    /// Count shown in session list (from summary endpoint — may differ from messages.count)
    var messageCount: Int
    var liveStatus: CodeServerLiveStatus?
    var workers: [CodeServerWorker]
    var todos: [CodeServerTodo]
    var totalTokens: Int
    var totalCost: Double
    var createdAt: String
    var updatedAt: String

    // Custom decoder — provides safe defaults for fields absent in summary responses
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        name         = try c.decode(String.self, forKey: .name)
        status       = (try? c.decode(CodeServerStatus.self, forKey: .status)) ?? .idle
        model        = (try? c.decode(String.self, forKey: .model)) ?? "minimax/minimax-m2.5"
        messages     = (try? c.decode([CodeServerMessage].self, forKey: .messages)) ?? []
        messageCount = (try? c.decode(Int.self, forKey: .messageCount)) ?? messages.count
        liveStatus   = try? c.decode(CodeServerLiveStatus.self, forKey: .liveStatus)
        workers      = (try? c.decode([CodeServerWorker].self, forKey: .workers)) ?? []
        todos        = (try? c.decode([CodeServerTodo].self, forKey: .todos)) ?? []
        totalTokens  = (try? c.decode(Int.self, forKey: .totalTokens)) ?? 0
        totalCost    = (try? c.decode(Double.self, forKey: .totalCost)) ?? 0
        createdAt    = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        updatedAt    = (try? c.decode(String.self, forKey: .updatedAt)) ?? ""
    }

    /// Manual constructor used when creating a session from the server's POST response.
    init(id: String, name: String, status: CodeServerStatus,
         model: String, createdAt: String, updatedAt: String = "") {
        self.id           = id
        self.name         = name
        self.status       = status
        self.model        = model
        self.messages     = []
        self.messageCount = 0
        self.liveStatus   = nil
        self.workers      = []
        self.todos        = []
        self.totalTokens  = 0
        self.totalCost    = 0
        self.createdAt    = createdAt
        self.updatedAt    = updatedAt.isEmpty ? createdAt : updatedAt
    }
}

// MARK: - CodeServerStatus

enum CodeServerStatus: String, Codable {
    case idle, working, done, error

    var displayName: String {
        switch self {
        case .idle:    return "Idle"
        case .working: return "Working"
        case .done:    return "Done"
        case .error:   return "Error"
        }
    }

    var color: Color {
        switch self {
        case .idle:    return .secondary
        case .working: return .accentNavi
        case .done:    return Color(naviHex: "4CAF50")
        case .error:   return Color(naviHex: "FF5252")
        }
    }

    var isActive: Bool { self == .working }
}

// MARK: - CodeServerMessage

struct CodeServerMessage: Identifiable, Codable {
    let id: String
    let role: String        // "user" | "assistant"
    let content: String
    let timestamp: String
    var toolCalls: [String]?
    var tokens: Int?
    var isWorker: Bool?
    var workerIndex: Int?
}

// MARK: - CodeServerLiveStatus

struct CodeServerLiveStatus: Codable {
    var phase: String?
    var tool: String?
    var iter: Int?
    var workersActive: Int?
    var elapsed: Int?
}

// MARK: - CodeServerWorker

struct CodeServerWorker: Identifiable, Codable {
    let id: String
    var index: Int
    var task: String
    var status: String      // "running" | "done" | "error"
    var output: String?
    var filesModified: [String]?
}

// MARK: - CodeServerTodo

struct CodeServerTodo: Identifiable, Codable {
    let id: String
    var text: String
    var done: Bool
}

// MARK: - CodeServerService
// Manages server-side code sessions on the Navi Brain server.
// All sessions run on the server — the app can be closed and sessions continue.
// Supports 10+ concurrent sessions with up to 8 parallel workers each.

@MainActor
final class CodeServerService: ObservableObject {
    static let shared = CodeServerService()

    // MARK: Published state

    @Published var sessions: [CodeServerSession] = []
    @Published var activeSession: CodeServerSession? = nil
    @Published var isLoading: Bool = false
    @Published var elapsedSeconds: Int = 0

    @Published var errorMessage: String? = nil {
        didSet {
            guard errorMessage != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 6_000_000_000) // Auto-clear after 6s
                self.errorMessage = nil
            }
        }
    }

    // MARK: Private state

    private var pollTimer: Timer?
    private var elapsedTimer: Timer?

    private var hasAnActiveSession: Bool {
        sessions.contains { $0.status == .working }
    }

    // MARK: Config

    private let baseURL = NaviBrainService.baseURL
    private let apiKey  = "navi-brain-2026"

    private let urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 60
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    private let decoder = JSONDecoder()

    // MARK: - Init

    private init() {
        Task { await loadSessions() }
    }

    deinit {
        pollTimer?.invalidate()
        elapsedTimer?.invalidate()
    }

    // MARK: - Load sessions
    // Server returns: { sessions: [ {id, name, status, model, messageCount, ...} ] }

    func loadSessions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await rawRequest("/code/sessions", method: "GET")
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr  = json["sessions"] as? [[String: Any]],
                  let sessData = try? JSONSerialization.data(withJSONObject: arr)
            else { return }

            let loaded = (try? decoder.decode([CodeServerSession].self, from: sessData)) ?? []
            sessions = loaded
            if hasAnActiveSession { startPolling() } else { stopPolling() }
        } catch {
            errorMessage = "Kunde inte hämta sessioner: \(error.localizedDescription)"
        }
    }

    // MARK: - Create session
    // Server returns: { sessionId, name, status, createdAt }

    @discardableResult
    func createSession(
        name: String,
        model: String = "minimax/minimax-m2.5"
    ) async throws -> CodeServerSession {
        var body: [String: Any] = ["name": name, "model": model]
        if let token = KeychainManager.shared.githubToken, !token.isEmpty {
            body["githubToken"] = token
        }

        let data = try await rawRequest("/code/sessions", method: "POST", body: body)
        let json  = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        let sessionId  = json["sessionId"]  as? String ?? UUID().uuidString
        let sName      = json["name"]        as? String ?? name
        let createdAt  = json["createdAt"]   as? String ?? ISO8601DateFormatter().string(from: Date())
        let session    = CodeServerSession(id: sessionId, name: sName,
                                           status: .idle, model: model, createdAt: createdAt)
        sessions.insert(session, at: 0)
        activeSession = session
        return session
    }

    // MARK: - Delete session

    func deleteSession(_ session: CodeServerSession) async {
        _ = try? await rawRequest("/code/sessions/\(session.id)", method: "DELETE")
        sessions.removeAll { $0.id == session.id }
        if activeSession?.id == session.id { activeSession = nil }
    }

    // MARK: - Send message

    func sendMessage(_ message: String, to session: CodeServerSession) async throws {
        var body: [String: Any] = ["message": message]
        if let token = KeychainManager.shared.githubToken, !token.isEmpty {
            body["githubToken"] = token
        }
        _ = try await rawRequest("/code/sessions/\(session.id)/message", method: "POST", body: body)

        // Optimistic status update
        updateSessionStatus(session.id, to: .working)
        startElapsedTimer()
        startPolling()
    }

    // MARK: - Stop session

    func stopSession(_ session: CodeServerSession) async {
        do {
            _ = try await rawRequest("/code/sessions/\(session.id)/stop", method: "POST")
        } catch {
            errorMessage = "Stopp misslyckades: \(error.localizedDescription)"
        }
    }

    // MARK: - Clear session

    func clearSession(_ session: CodeServerSession) async {
        do {
            _ = try await rawRequest("/code/sessions/\(session.id)/clear", method: "POST")
            _ = await refreshSession(session.id)
        } catch {
            errorMessage = "Rensning misslyckades: \(error.localizedDescription)"
        }
    }

    // MARK: - Refresh single session
    // Server returns: { session: { full session object } }

    @discardableResult
    func refreshSession(_ sessionId: String) async -> CodeServerSession? {
        guard let data = try? await rawRequest("/code/sessions/\(sessionId)", method: "GET"),
              let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sDict = json["session"] as? [String: Any],
              let sData = try? JSONSerialization.data(withJSONObject: sDict),
              let updated = try? decoder.decode(CodeServerSession.self, from: sData)
        else { return nil }

        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx] = updated
        }
        if activeSession?.id == sessionId {
            activeSession = updated
        }
        return updated
    }

    // MARK: - Polling
    // Server /code/live returns: { sessions: { [id]: { status, liveStatus, name } } }

    func startPolling(interval: TimeInterval = 2.0) {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.pollActiveSessions() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func pollActiveSessions() async {
        // Track which sessions were active before this poll
        let wasWorking = Set(sessions.filter { $0.status == .working }.map { $0.id })

        do {
            let data = try await rawRequest("/code/live", method: "GET")
            guard let json     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessDict = json["sessions"] as? [String: Any]
            else { return }

            for (id, entryAny) in sessDict {
                guard let entry     = entryAny as? [String: Any],
                      let statusRaw = entry["status"] as? String,
                      let status    = CodeServerStatus(rawValue: statusRaw)
                else { continue }

                var liveStatus: CodeServerLiveStatus? = nil
                if let lsRaw  = entry["liveStatus"] as? [String: Any],
                   let lsData = try? JSONSerialization.data(withJSONObject: lsRaw) {
                    liveStatus = try? decoder.decode(CodeServerLiveStatus.self, from: lsData)
                }

                var workers: [CodeServerWorker] = []
                if let wRaw  = entry["workers"] as? [[String: Any]],
                   let wData = try? JSONSerialization.data(withJSONObject: wRaw) {
                    workers = (try? decoder.decode([CodeServerWorker].self, from: wData)) ?? []
                }

                if let idx = sessions.firstIndex(where: { $0.id == id }) {
                    sessions[idx].status     = status
                    sessions[idx].liveStatus = liveStatus
                    sessions[idx].workers    = workers
                }
                if activeSession?.id == id {
                    activeSession?.status     = status
                    activeSession?.liveStatus = liveStatus
                    activeSession?.workers    = workers
                }
            }
        } catch {
            // Transient poll errors — ignore silently
        }

        // For sessions that just completed, fetch full messages
        let nowCompleted = sessions.filter {
            wasWorking.contains($0.id) && $0.status != .working
        }
        for session in nowCompleted {
            _ = await refreshSession(session.id)
        }

        if !hasAnActiveSession {
            stopPolling()
            stopElapsedTimer()
        }
    }

    // MARK: - Elapsed timer

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.elapsedSeconds += 1 }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    func elapsedString() -> String {
        elapsedSeconds < 60
            ? "\(elapsedSeconds)s"
            : "\(elapsedSeconds / 60)m \(elapsedSeconds % 60)s"
    }

    // MARK: - Private helpers

    private func updateSessionStatus(_ sessionId: String, to status: CodeServerStatus) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].status = status
        }
        if activeSession?.id == sessionId {
            activeSession?.status = status
        }
    }

    // MARK: - Core HTTP request

    /// Performs an authenticated HTTP request to the Navi Brain server.
    private func rawRequest(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(apiKey,            forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Forward GitHub token so server agents have repository access
        if let token = KeychainManager.shared.githubToken, !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "x-github-token")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "CodeServer", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return data
    }
}
