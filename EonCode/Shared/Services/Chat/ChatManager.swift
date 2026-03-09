import Foundation
import Combine

// MARK: - ChatManager
// Manages pure chat conversations (no project/agent context).

@MainActor
final class ChatManager: ObservableObject {
    static let shared = ChatManager()

    @Published var conversations: [ChatConversation] = []
    @Published var activeConversation: ChatConversation?
    @Published var isStreaming = false
    @Published var streamingText = ""
    @Published var streamingScrollTick = 0   // increments every ~80 chars; used instead of .count to avoid O(n)
    @Published var isLoading = true

    private let store = iCloudChatStore.shared
    private let api = ClaudeAPIClient.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Task {
            await load()
            isLoading = false
        }

        // Reload conversations when iCloud syncs
        NotificationCenter.default.publisher(for: .iCloudDidSync)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.load()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load

    func load() async {
        do {
            let loaded = try await store.loadAll()
            let loadedIDs = Set(loaded.map(\.id))
            let unsaved = conversations.filter { !loadedIDs.contains($0.id) }
            conversations = loaded + unsaved
        } catch {
            NaviLog.error("ChatManager: kunde inte ladda konversationer", error: error)
        }
    }

    // MARK: - New conversation

    func newConversation(model: ClaudeModel? = nil) -> ChatConversation {
        let model = model ?? SettingsStore.shared.defaultModel
        let conv = ChatConversation(model: model)
        conversations.insert(conv, at: 0)
        activeConversation = conv
        Task {
            do {
                try await store.save(conv)
            } catch {
                NaviLog.error("ChatManager: kunde inte spara ny konversation", error: error)
            }
        }
        return conv
    }

    // MARK: - Send message (streaming)

    func send(
        text: String,
        images: [Data] = [],
        in conversation: inout ChatConversation,
        voiceInstruction: String? = nil,
        onToken: @escaping (String) -> Void
    ) async throws {
        let userMsg = PureChatMessage(role: .user, content: text, imageData: images.isEmpty ? nil : images)
        conversation.messages.append(userMsg)
        conversation.updatedAt = Date()

        // Immediately surface the user message in the UI
        activeConversation = conversation
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        }

        // Build API messages
        let apiMessages = buildAPIMessages(from: conversation)

        // Build system prompt with memories + active project context
        let memoryCtx = MemoryManager.shared.memoryContext()
        var systemPrompt = "Du är Navi — en kunnig AI-assistent specialiserad på kodning, design och teknik. Var koncis och professionell. Gå rakt på sak — skriv korta, tydliga svar. Tänk högt kort vid komplexa frågor.\(memoryCtx)"

        // Inject active project context so the chat knows about cloned repos
        if let project = ProjectStore.shared.activeProject {
            systemPrompt += "\n\nAktivt projekt: \(project.name)"
            if let repo = project.githubRepoFullName {
                systemPrompt += " (GitHub: \(repo))"
                if let branch = project.githubBranch {
                    systemPrompt += " på branch \(branch)"
                }
            }
        }

        // View context
        if !MessageBuilder.currentViewContext.isEmpty {
            systemPrompt += "\n\nAKTIV VY: \(MessageBuilder.currentViewContext)"
        }

        // Voice mode instruction (appended to system prompt, not visible in chat)
        if let voiceInst = voiceInstruction {
            systemPrompt += "\n\n[RÖSTLÄGE] \(voiceInst)"
        }

        isStreaming = true
        streamingText = ""
        defer { isStreaming = false; streamingText = "" }

        var fullText = ""
        var finalUsage: TokenUsage?
        // Throttle UI updates: only publish streamingText every ~60ms (~16fps)
        // to avoid re-rendering the entire chat view on every token
        var lastPublish = Date.distantPast
        var charsSinceScroll = 0

        // Route streaming by provider
        let eventHandler: (StreamEvent) -> Void = { [self] event in
            switch event {
            case .contentBlockDelta(_, let delta):
                if case .text(let chunk) = delta {
                    fullText += chunk
                    charsSinceScroll += chunk.count
                    onToken(chunk)
                    let now = Date()
                    if now.timeIntervalSince(lastPublish) >= 0.06 {
                        self.streamingText = fullText
                        if charsSinceScroll >= 80 {
                            self.streamingScrollTick += 1
                            charsSinceScroll = 0
                        }
                        lastPublish = now
                    }
                }
            case .messageDelta(_, let usage):
                finalUsage = usage
            default:
                break
            }
        }

        switch conversation.model.provider {
        case .anthropic:
            try await api.streamMessage(
                messages: apiMessages,
                model: conversation.model,
                systemPrompt: systemPrompt,
                tools: nil,
                usePromptCaching: true,
                onEvent: eventHandler
            )
        case .xai:
            try await XAIClient.shared.streamChatCompletion(
                messages: apiMessages,
                model: conversation.model,
                systemPrompt: systemPrompt,
                onEvent: eventHandler
            )
        }

        // Calculate cost
        let costSEK: Double
        if let usage = finalUsage {
            let (_, sek) = CostCalculator.shared.calculate(usage: usage, model: conversation.model)
            costSEK = sek
            conversation.totalCostSEK += sek
            CostTracker.shared.record(usage: usage, model: conversation.model)
        } else {
            costSEK = 0
        }

        let assistantMsg = PureChatMessage(
            role: .assistant,
            content: ResponseCleaner.clean(fullText),
            costSEK: costSEK,
            model: conversation.model,
            tokenUsage: finalUsage
        )
        conversation.messages.append(assistantMsg)
        conversation.updatedAt = Date()

        // Auto-generate title from first exchange
        if conversation.title == "Ny chatt" && conversation.messages.count >= 2 {
            conversation.title = await generateTitle(for: conversation)
        }

        // Persist
        try? await store.save(conversation)

        // Update published list
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        }

        // Extract memories every 10 new messages (not every single message after the 6th)
        let msgCount = conversation.messages.count
        if msgCount >= 6 && msgCount % 10 == 0 {
            let messages = conversation.messages
            let convId = conversation.id
            Task {
                await MemoryManager.shared.extractMemories(
                    from: messages,
                    conversationId: convId
                )
            }
        }
    }

    // MARK: - Delete

    func delete(_ conversation: ChatConversation) async {
        try? await store.delete(id: conversation.id)
        conversations.removeAll { $0.id == conversation.id }
        if activeConversation?.id == conversation.id {
            activeConversation = conversations.first
        }
    }

    // MARK: - Search

    func search(query: String) async -> [ChatConversation] {
        await store.search(query: query)
    }

    // MARK: - Auto-generate title

    func generateTitle(for conversation: ChatConversation) async -> String {
        guard let first = conversation.messages.first(where: { $0.role == .user }) else {
            return "Ny chatt"
        }

        // Try AI-generated title via Haiku (fast + cheap)
        if KeychainManager.shared.anthropicAPIKey?.isEmpty == false {
            let prompt = "Ge denna konversation en kort titel (max 5 ord, inget citattecken). Konversation: \(first.content.prefix(300))"
            do {
                let (title, _) = try await api.sendMessage(
                    messages: [ChatMessage(role: .user, content: [.text(prompt)])],
                    model: .haiku,
                    systemPrompt: "Svara med BARA titeln. Max 5 ord. Inget citattecken.",
                    maxTokens: 30
                )
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !trimmed.isEmpty && trimmed.count < 60 {
                    return trimmed
                }
            } catch {
                // Fall back to truncation
            }
        }

        // Fallback: truncate first message
        let preview = String(first.content.prefix(50))
        return preview.isEmpty ? "Ny chatt" : preview
    }

    // MARK: - Build API messages

    private func buildAPIMessages(from conversation: ChatConversation) -> [ChatMessage] {
        conversation.messages.map { msg in
            ChatMessage(role: msg.role, content: msg.apiContent)
        }
    }
}
