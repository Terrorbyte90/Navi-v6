import Foundation

// MARK: - Pure Chat Conversation (no project/agent context)

struct ChatConversation: Codable, Identifiable {
    let id: UUID
    var title: String
    var messages: [PureChatMessage]
    var model: ClaudeModel
    var createdAt: Date
    var updatedAt: Date
    var totalCostSEK: Double
    var memories: [String]

    init(model: ClaudeModel = .haiku) {
        self.id = UUID()
        self.title = "Ny chatt"
        self.messages = []
        self.model = model
        self.createdAt = Date()
        self.updatedAt = Date()
        self.totalCostSEK = 0
        self.memories = []
    }
}

struct PureChatMessage: Codable, Identifiable {
    let id: UUID
    let role: MessageRole
    let content: String
    let imageData: [Data]?
    let timestamp: Date
    let costSEK: Double?
    let model: ClaudeModel?
    let tokenUsage: TokenUsage?
    var memoriesInContext: [String]   // memory facts that were active when this message was generated
    var toolCallNames: [String]?      // tool calls executed to produce this response

    init(
        role: MessageRole,
        content: String,
        imageData: [Data]? = nil,
        costSEK: Double? = nil,
        model: ClaudeModel? = nil,
        tokenUsage: TokenUsage? = nil,
        memoriesInContext: [String] = [],
        toolCallNames: [String]? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.imageData = imageData
        self.timestamp = Date()
        self.costSEK = costSEK
        self.model = model
        self.tokenUsage = tokenUsage
        self.memoriesInContext = memoriesInContext
        self.toolCallNames = toolCallNames
    }

    // Convenience for building API request content
    var apiContent: [MessageContent] {
        var parts: [MessageContent] = []
        if let imgs = imageData {
            for data in imgs {
                parts.append(.image(data, mimeType: "image/jpeg"))
            }
        }
        parts.append(.text(content))
        return parts
    }
}
