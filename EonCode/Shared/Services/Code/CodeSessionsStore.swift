import Foundation
import SwiftUI
#if os(iOS)
import WidgetKit
import BackgroundTasks
#endif

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

// MARK: - Widget data bridge (matches NaviWidgetSession in NaviWidget extension)

private struct WidgetSessionData: Codable {
    var id: String
    var task: String
    var status: String
    var model: String
    var todosDone: Int
    var todosTotal: Int
    var updatedAt: Date
}

// MARK: - CodeSessionsStore

@MainActor
final class CodeSessionsStore: ObservableObject {
    static let shared = CodeSessionsStore()

    @Published var sessions: [RemoteCodeSession] = []
    @Published var isLoading = false
    @Published var fetchError: String?

    private init() {
        startPolling()
    }

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
                try? await Task.sleep(nanoseconds: 10_000_000_000)
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
            syncToWidget()
        } catch {
            fetchError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Widget sync

    private func syncToWidget() {
        #if os(iOS)
        let widgetData = sessions.prefix(5).map { s in
            WidgetSessionData(
                id: s.id,
                task: s.task,
                status: s.status,
                model: s.modelDisplayName,
                todosDone: s.doneCount,
                todosTotal: s.todos.count,
                updatedAt: ISO8601DateFormatter().date(from: s.updatedAt) ?? Date()
            )
        }
        if let encoded = try? JSONEncoder().encode(Array(widgetData)) {
            UserDefaults(suiteName: "group.com.tedsvard.navi")?.set(encoded, forKey: "naviWidgetSessions")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "NaviWidget")
        #endif
    }

    // MARK: - Background check (called by BGAppRefreshTask)

    /// Fetch sessions once and fire a notification if any just finished.
    /// Returns true if a notification was fired.
    static func backgroundCheckAndNotify() async -> Bool {
        let store = UserDefaults.standard
        let serverURL = store.string(forKey: "naviServerURL") ?? "http://209.38.98.107:3001"
        let apiKey    = store.string(forKey: "naviServerAPIKey") ?? "navi-brain-2026"

        guard let url = URL(string: "\(serverURL)/code/sessions?key=\(apiKey)") else { return false }

        // Load previously known running sessions
        let knownRunningKey = "bgKnownRunningSessions"
        let knownRunning = Set(store.stringArray(forKey: knownRunningKey) ?? [])

        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return false }
        struct Resp: Decodable {
            struct S: Decodable { let id: String; let status: String; let task: String; let model: String }
            let sessions: [S]
        }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return false }

        let nowRunning  = Set(resp.sessions.filter { $0.status == "running" }.map { $0.id })
        let justDone    = resp.sessions.filter { knownRunning.contains($0.id) && $0.status == "done" }
        let justFailed  = resp.sessions.filter { knownRunning.contains($0.id) && $0.status == "error" }

        // Persist new running set
        store.set(Array(nowRunning), forKey: knownRunningKey)

        // Fire notifications for completed sessions
        for s in justDone {
            await CodeNotificationHelper.sendCompletionNotification(task: s.task, summary: "Klar")
        }
        for s in justFailed {
            await CodeNotificationHelper.sendErrorNotification(task: s.task, error: "Agenten stötte på ett fel")
        }

        return !justDone.isEmpty || !justFailed.isEmpty
    }

    // MARK: - Actions

    func switchToSession(_ session: RemoteCodeSession) {
        ServerCodeSession.shared.resumeSession(session.id)
    }

    var runningSessions: [RemoteCodeSession] { sessions.filter { $0.isRunning } }
    var recentSessions: [RemoteCodeSession] { sessions.filter { !$0.isRunning } }
}
