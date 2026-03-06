import Foundation

// MARK: - ChatManager
// Manages pure chat conversations (no project/agent context).

@MainActor
final class ChatManager: ObservableObject {
    static let shared = ChatManager()

    @Published var conversations: [ChatConversation] = []
    @Published var activeConversation: ChatConversation?
    @Published var isStreaming = false
    @Published var streamingText = ""

    private let store = iCloudChatStore.shared
    private let api = ClaudeAPIClient.shared

    private init() {
        Task { await load() }
    }

    // MARK: - Load

    func load() async {
        conversations = (try? await store.loadAll()) ?? []
    }

    // MARK: - New conversation

    func newConversation(model: ClaudeModel = .sonnet45) -> ChatConversation {
        let conv = ChatConversation(model: model)
        conversations.insert(conv, at: 0)
        activeConversation = conv
        Task { try? await store.save(conv) }
        return conv
    }

    // MARK: - Send message (streaming)

    func send(
        text: String,
        images: [Data] = [],
        in conversation: inout ChatConversation,
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

        // Build system prompt with memories
        let memoryCtx = MemoryManager.shared.memoryContext()
        let systemPrompt = "Du är en hjälpsam AI-assistent.\(memoryCtx)"

        isStreaming = true
        streamingText = ""
        defer { isStreaming = false; streamingText = "" }

        var fullText = ""
        var finalUsage: TokenUsage?

        try await api.streamMessage(
            messages: apiMessages,
            model: conversation.model,
            systemPrompt: systemPrompt,
            tools: nil,
            usePromptCaching: true
        ) { event in
            switch event {
            case .contentBlockDelta(_, let delta):
                if case .text(let chunk) = delta {
                    fullText += chunk
                    self.streamingText = fullText
                    onToken(chunk)
                }
            case .messageDelta(_, let usage):
                finalUsage = usage
            default:
                break
            }
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
            content: fullText,
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

        // Extract memories after substantial conversations
        if conversation.messages.count >= 6 {
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
        let preview = String(first.content.prefix(60))
        // Simple title: use first user message preview
        return preview.isEmpty ? "Ny chatt" : preview
    }

    // MARK: - Build API messages

    private func buildAPIMessages(from conversation: ChatConversation) -> [ChatMessage] {
        conversation.messages.map { msg in
            ChatMessage(role: msg.role, content: msg.apiContent)
        }
    }
}
