import Foundation

// Agent planner — breaks down high-level instructions into steps
@MainActor
final class AgentPlanner {
    static let shared = AgentPlanner()
    private init() {}

    func plan(instruction: String, project: NaviProject?) async throws -> [AgentStep] {
        let projectInfo = project.map { "Projekt: \($0.name) at \($0.rootPath)" } ?? ""

        let planPrompt = """
        Bryt ned denna uppgift i tydliga steg. Returnera ENDAST en JSON-array med steg.

        Uppgift: \(instruction)
        \(projectInfo)

        Format:
        [{"step": 1, "action": "read_file", "description": "Läs main.swift", "params": {"path": "main.swift"}}, ...]

        Tillgängliga actions: read_file, write_file, move_file, delete_file, create_directory, list_directory, run_command, search_files, get_api_key, build_project, download_file, think
        """

        let conv = Conversation(projectID: project?.id ?? UUID())
        let (text, _) = try await ClaudeAPIClient.shared.sendMessage(
            messages: [ChatMessage(role: .user, content: [.text(planPrompt)])],
            model: .haiku,
            systemPrompt: "Du är en planläggare. Returnera alltid giltig JSON.",
            maxTokens: 2048
        )

        // Extract JSON from response
        let json = extractJSON(from: text)
        guard let data = json.data(using: .utf8),
              let steps = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        let taskID = UUID()
        return steps.enumerated().map { i, step in
            let actionName = step["action"] as? String ?? "think"
            let params = step["params"] as? [String: String] ?? [:]
            let action = buildAction(name: actionName, params: params, step: step)

            return AgentStep(taskID: taskID, index: i, action: action)
        }
    }

    private func buildAction(name: String, params: [String: String], step: [String: Any]) -> AgentAction {
        switch name {
        case "read_file": return .readFile(path: params["path"] ?? "")
        case "write_file": return .writeFile(path: params["path"] ?? "", content: params["content"] ?? "")
        case "move_file": return .moveFile(from: params["from"] ?? "", to: params["to"] ?? "")
        case "delete_file": return .deleteFile(path: params["path"] ?? "")
        case "create_directory": return .createDirectory(path: params["path"] ?? "")
        case "list_directory": return .listDirectory(path: params["path"] ?? "")
        case "run_command": return .runCommand(cmd: params["cmd"] ?? "")
        case "search_files": return .searchFiles(query: params["query"] ?? "")
        case "get_api_key": return .getAPIKey(service: params["service"] ?? "")
        case "build_project": return .buildProject(path: params["path"] ?? "")
        case "download_file": return .downloadFile(url: params["url"] ?? "", destination: params["destination"] ?? "")
        case "think": return .think(reasoning: step["description"] as? String ?? "")
        default: return .custom(name: name, params: params)
        }
    }

    private func extractJSON(from text: String) -> String {
        if let start = text.range(of: "["),
           let end = text.range(of: "]", options: .backwards) {
            return String(text[start.lowerBound...end.upperBound])
        }
        return "[]"
    }
}
