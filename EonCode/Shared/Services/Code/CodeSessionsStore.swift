import Foundation
import SwiftUI

// MARK: - Remote session model (mirrors server /code/sessions response)

struct RemoteCodeSession: Identifiable, Decodable {
    let id: String
    let task: String
    let model: String
    let status: String          // idle | running | done | error | stopped
    let createdAt: String
    let updatedAt: String
    let todos: [ServerTodoItem]
    let gitCheckpoints: Int

    var statusIcon: String {
        switch status {
        case "running": return "bolt.circle.fill"
        case "done":    return "checkmark.circle.fill"
        case "error":   return "exclamationmark.circle.fill"
        case "stopped": return "stop.circle.fill"
        default:        return "circle"
        }
    }

    var statusColor: Color {
        switch status {
        case "running": return NaviTheme.warning
        case "done":    return NaviTheme.success
        case "error":   return NaviTheme.error
        case "stopped": return .secondary
        default:        return .secondary
        }
    }

    var taskPreview: String { String(task.prefix(80)) }
    var isRunning: Bool { status == "running" }
    var doneCount: Int { todos.filter { $0.done }.count }

    var timeAgo: String {
        guard let date = ISO8601DateFormatter().date(from: updatedAt) else { return "" }
        return date.relativeString
    }

    var modelDisplayName: String {
        switch model {
        case "minimax":  return "MiniMax"
        case "qwen":     return "Qwen3"
        case "deepseek": return "DeepSeek"
        case "claude":   return "Claude"
        default:         return model
        }
    }
}

// MARK: - CodeSessionsStore

@MainActor
final class CodeSessionsStore: ObservableObject {
    static let shared = CodeSessionsStore()

    @Published var sessions: [RemoteCodeSession] = []
    @Published var isLoading = false
    @Published var fetchError: String?

    private init() {}

    private var pollTask: Task<Void, Never>?

    private var serverURL: String {
        UserDefaults.standard.string(forKey: "naviServerURL") ?? "http://209.38.98.107:3001"
    }

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "naviServerAPIKey") ?? "navi-brain-2026"
    }

    // MARK: - Polling

    func startPolling() {
        guard pollTask == nil else { return }
        Task { await fetchSessions() }          // immediate first load
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.fetchSessions()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func fetchSessions() async {
        guard let url = URL(string: "\(serverURL)/code/sessions?key=\(apiKey)") else { return }
        do {
            isLoading = true
            fetchError = nil
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Response: Decodable { let sessions: [RemoteCodeSession] }
            let resp = try JSONDecoder().decode(Response.self, from: data)
            sessions = resp.sessions
        } catch {
            fetchError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Actions

    func switchToSession(_ session: RemoteCodeSession) {
        ServerCodeSession.shared.resumeSession(session.id)
    }

    var runningSessions: [RemoteCodeSession] { sessions.filter { $0.isRunning } }
    var recentSessions: [RemoteCodeSession] { sessions.filter { !$0.isRunning } }
}
