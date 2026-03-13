import Foundation
import Combine

@MainActor
final class AgentPool: ObservableObject {
    static let shared = AgentPool()

    @Published var agents: [UUID: ProjectAgent] = [:]

    private init() {}

    func agent(for project: NaviProject) -> ProjectAgent {
        if let existing = agents[project.id] {
            return existing
        }
        let agent = ProjectAgent(project: project)
        agents[project.id] = agent
        return agent
    }

    func removeAgent(for projectId: UUID) {
        if let agent = agents.removeValue(forKey: projectId) {
            agent.stop()
        }
    }

    func stopAll() {
        for agent in agents.values {
            agent.stop()
        }
    }

    func removeAll() {
        stopAll()
        agents.removeAll()
    }

    var activeCount: Int {
        agents.values.filter { $0.isRunning }.count
    }
}

@MainActor
final class ProjectAgent: ObservableObject, Identifiable {
    let id: UUID
    let project: NaviProject

    @Published var isRunning = false
    @Published var currentStatus = ""
    @Published var conversation: Conversation
    @Published var conversationHistory: [Conversation] = []
    @Published var streamingText = ""
    @Published var lastCostSEK: Double = 0
    @Published var sessionCostSEK: Double = 0
    @Published var activeFileNames: [String] = []
    @Published var activeCodeSnippet: String = ""
    @Published var todoItems: [AgentTodoItem] = []

    struct AgentTodoItem: Identifiable {
        let id = UUID()
        let text: String
        let isDone: Bool
    }

    private let engine = AgentEngine()
    private var task: Task<Void, Never>?

    // Completion callback — called when current message finishes (used by PromptQueue)
    private var completionHandler: (() -> Void)?

    init(project: NaviProject) {
        self.id = project.id
        self.project = project
        self.conversation = Conversation(projectID: project.id, model: project.activeModel)
        engine.setProject(project)

        // Load saved conversations from iCloud
        Task {
            await ConversationStore.shared.loadConversations(for: project.id)
            let saved = ConversationStore.shared.conversationsForProject(project.id)
            self.conversationHistory = saved
            // Resume latest conversation if it exists
            if let latest = saved.first {
                self.conversation = latest
            }
        }
    }

    // MARK: - Conversation management

    func newConversation() {
        // Save current conversation if it has messages
        if !conversation.messages.isEmpty {
            Task { await persistConversation() }
        }
        conversation = Conversation(projectID: project.id, model: project.activeModel)
        streamingText = ""
    }

    func switchToConversation(_ conv: Conversation) {
        // Save current conversation first
        if !conversation.messages.isEmpty {
            Task { await persistConversation() }
        }
        conversation = conv
        streamingText = ""
    }

    private func persistConversation() async {
        await ConversationStore.shared.save(conversation)
        // Update local history
        if let idx = conversationHistory.firstIndex(where: { $0.id == conversation.id }) {
            conversationHistory[idx] = conversation
        } else {
            conversationHistory.insert(conversation, at: 0)
        }
    }

    /// Send a message. `onComplete` is called when the agent finishes (used by PromptQueue for sequencing).
    func sendMessage(
        _ text: String,
        images: [Data] = [],
        isAgentMode: Bool = false,
        onComplete: (() -> Void)? = nil
    ) {
        // If already running, queue the message instead of dropping it
        guard !isRunning else {
            // Enqueue via PromptQueue so it runs after current task
            let queue = PromptQueue.queue(for: project.id)
            queue.enqueue(text: text, isAgentMode: isAgentMode, iterations: 1)
            return
        }

        completionHandler = onComplete

        task = Task {
            isRunning = true
            streamingText = ""
            defer {
                isRunning = false
                let handler = completionHandler
                completionHandler = nil
                handler?()
                // Persist conversation after each message exchange
                Task { await self.persistConversation() }
                // Extract memories after substantial conversations
                if self.conversation.messages.count >= 6 {
                    let messages = self.conversation.messages
                    let convId = self.conversation.id
                    Task {
                        await MemoryManager.shared.extractMemoriesFromAgent(
                            messages: messages,
                            conversationId: convId
                        )
                    }
                }
                // Auto-push to GitHub if project is linked to a repo
                Task { await self.autoGitHubSync() }
            }

            if isAgentMode {
                let agentTask = AgentTask(projectID: project.id, instruction: text)
                var conv = conversation
                await engine.run(
                    task: agentTask,
                    conversation: &conv,
                    onUpdate: { [weak self] update in
                        self?.streamingText = update
                        // Extract file names from tool update messages
                        self?.parseStatusAndFiles(update)
                    }
                )
                conversation = conv
                activeFileNames = []
                activeCodeSnippet = ""
                todoItems = []
            } else {
                var conv = conversation
                await engine.sendChat(
                    userText: text,
                    images: images,
                    conversation: &conv,
                    onToken: { [weak self] token in
                        self?.streamingText += token
                    },
                    onComplete: { [weak self] usage in
                        guard let self = self else { return }
                        self.streamingText = ""
                    },
                    onError: { [weak self] error in
                        self?.currentStatus = error.localizedDescription
                        self?.streamingText = ""
                    }
                )
                conversation = conv
            }
        }
    }

    /// Parse agent update text to extract current status, file names, code snippets and TODO items.
    private func parseStatusAndFiles(_ update: String) {
        let toolNames = ["read_file", "write_file", "move_file", "delete_file", "create_directory",
                         "list_directory", "run_command", "search_files", "build_project", "download_file",
                         "deploy_testflight"]

        var detectedStatus = ""
        var detectedFiles: [String] = []

        for tool in toolNames {
            if update.contains(tool) {
                switch tool {
                case "write_file":  detectedStatus = "Skriver fil…"
                case "read_file":   detectedStatus = "Läser fil…"
                case "run_command": detectedStatus = "Kör kommando…"
                case "build_project": detectedStatus = "Bygger projekt…"
                case "search_files": detectedStatus = "Söker i filer…"
                case "delete_file": detectedStatus = "Tar bort fil…"
                case "move_file":   detectedStatus = "Flyttar fil…"
                case "list_directory": detectedStatus = "Listar katalog…"
                case "create_directory": detectedStatus = "Skapar mapp…"
                case "download_file": detectedStatus = "Laddar ned…"
                case "deploy_testflight": detectedStatus = "Deploying till TestFlight…"
                default: break
                }

                // Extract file path
                let parts = update.components(separatedBy: ": ")
                if parts.count > 1 {
                    let pathStr = parts.dropFirst().joined(separator: ": ")
                    let fileName = (pathStr as NSString).lastPathComponent
                        .components(separatedBy: " ").first ?? ""
                    if !fileName.isEmpty && fileName.contains(".") {
                        detectedFiles = [String(fileName.prefix(40))]
                    }
                }

                // Extract code snippet for write_file
                if tool == "write_file" {
                    extractCodeSnippet(from: update)
                }
            }
        }

        if update.contains("Tänker") || update.contains("Planerar") {
            detectedStatus = update.prefix(60).description
        }

        if !detectedStatus.isEmpty { currentStatus = detectedStatus }
        if !detectedFiles.isEmpty { activeFileNames = detectedFiles }

        // Parse TODO items from streaming text
        parseTodoItems(from: update)
    }

    /// Extract a brief code snippet from write_file content for the live preview card.
    private func extractCodeSnippet(from update: String) {
        // Look for content between "content" parameter markers or code blocks
        let lines = update.components(separatedBy: "\n")
        // Find lines that look like code (indented, contain common code patterns)
        let codeLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty &&
                   !trimmed.hasPrefix("✅") &&
                   !trimmed.hasPrefix("⚙️") &&
                   (trimmed.contains("func ") || trimmed.contains("let ") || trimmed.contains("var ") ||
                    trimmed.contains("import ") || trimmed.contains("class ") || trimmed.contains("struct ") ||
                    trimmed.contains("return ") || trimmed.contains("{") || trimmed.contains("}") ||
                    trimmed.contains("//") || trimmed.contains("guard ") || trimmed.contains("if ") ||
                    trimmed.hasPrefix(".") || trimmed.hasPrefix("@") ||
                    trimmed.contains("def ") || trimmed.contains("const ") || trimmed.contains("function "))
        }
        if !codeLines.isEmpty {
            activeCodeSnippet = codeLines.prefix(5).joined(separator: "\n")
        }
    }

    /// Parse TODO/checklist items from streaming text.
    private func parseTodoItems(from text: String) {
        let lines = text.components(separatedBy: "\n")
        var items: [AgentTodoItem] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match "- [ ] task" or "- [x] task" patterns
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let taskText = String(trimmed.dropFirst(6))
                if !taskText.isEmpty { items.append(AgentTodoItem(text: taskText, isDone: true)) }
            } else if trimmed.hasPrefix("- [ ] ") {
                let taskText = String(trimmed.dropFirst(6))
                if !taskText.isEmpty { items.append(AgentTodoItem(text: taskText, isDone: false)) }
            }
            // Match numbered lists like "1. ✅ task" or "1. task"
            else if let match = trimmed.range(of: #"^\d+\.\s*✅\s*"#, options: .regularExpression) {
                let taskText = String(trimmed[match.upperBound...])
                if !taskText.isEmpty { items.append(AgentTodoItem(text: taskText, isDone: true)) }
            } else if let match = trimmed.range(of: #"^\d+\.\s*⬜\s*"#, options: .regularExpression) {
                let taskText = String(trimmed[match.upperBound...])
                if !taskText.isEmpty { items.append(AgentTodoItem(text: taskText, isDone: false)) }
            }
        }

        if !items.isEmpty { todoItems = items }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        let handler = completionHandler
        completionHandler = nil
        handler?()
        // Persist on stop too
        if !conversation.messages.isEmpty {
            Task { await persistConversation() }
        }
    }

    // MARK: - Auto GitHub sync after agent run

    private func autoGitHubSync() async {
        guard let repoFullName = project.githubRepoFullName,
              let repo = GitHubManager.shared.repos.first(where: { $0.fullName == repoFullName })
        else { return }
        await GitHubManager.shared.autoCommitAndPush(repo: repo, changedFiles: [])
    }
}
