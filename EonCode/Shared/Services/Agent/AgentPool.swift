import Foundation
import Combine

@MainActor
final class AgentPool: ObservableObject {
    static let shared = AgentPool()

    @Published var agents: [UUID: ProjectAgent] = [:]

    private init() {}

    func agent(for project: EonProject) -> ProjectAgent {
        if let existing = agents[project.id] {
            return existing
        }
        let agent = ProjectAgent(project: project)
        agents[project.id] = agent
        return agent
    }

    func stopAll() {
        for agent in agents.values {
            agent.stop()
        }
    }

    var activeCount: Int {
        agents.values.filter { $0.isRunning }.count
    }
}

@MainActor
final class ProjectAgent: ObservableObject, Identifiable {
    let id: UUID
    let project: EonProject

    @Published var isRunning = false
    @Published var currentStatus = ""
    @Published var conversation: Conversation
    @Published var conversationHistory: [Conversation] = []
    @Published var streamingText = ""
    @Published var lastCostSEK: Double = 0
    @Published var sessionCostSEK: Double = 0

    private let engine = AgentEngine()
    private var task: Task<Void, Never>?

    // Completion callback — called when current message finishes (used by PromptQueue)
    private var completionHandler: (() -> Void)?

    init(project: EonProject) {
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
                        self?.currentStatus = update
                    }
                )
                conversation = conv
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
                        let (_, sek) = CostCalculator.shared.calculate(usage: usage, model: self.conversation.model)
                        self.lastCostSEK = sek
                        self.sessionCostSEK += sek
                        self.streamingText = ""
                        CostTracker.shared.record(usage: usage, model: self.conversation.model)
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
