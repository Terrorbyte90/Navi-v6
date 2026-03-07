import Foundation

// MARK: - Request / Response types

struct ClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [ClaudeRequestMessage]
    let system: [SystemBlock]?
    let stream: Bool
    let tools: [ClaudeTool]?

    enum CodingKeys: String, CodingKey {
        case model, stream, tools
        case maxTokens = "max_tokens"
        case messages
        case system
    }
}

struct SystemBlock: Encodable {
    let type: String
    let text: String
    let cacheControl: CacheControl?

    enum CodingKeys: String, CodingKey {
        case type, text
        case cacheControl = "cache_control"
    }
}

struct CacheControl: Encodable {
    let type: String = "ephemeral"
}

struct ClaudeRequestMessage: Encodable {
    let role: String
    let content: [ClaudeContentBlock]
}

struct ClaudeContentBlock: Encodable {
    let type: String
    let text: String?
    let source: ImageSource?
    let id: String?
    let name: String?
    let input: [String: AnyCodable]?
    let toolUseId: String?
    let content: String?
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type, text, source, id, name, input, content
        case toolUseId = "tool_use_id"
        case isError = "is_error"
    }

    static func text(_ text: String, cache: Bool = false) -> ClaudeContentBlock {
        ClaudeContentBlock(type: "text", text: text, source: nil, id: nil, name: nil, input: nil, toolUseId: nil, content: nil, isError: nil)
    }

    static func image(data: Data, mimeType: String) -> ClaudeContentBlock {
        let src = ImageSource(type: "base64", mediaType: mimeType, data: data.base64EncodedString())
        return ClaudeContentBlock(type: "image", text: nil, source: src, id: nil, name: nil, input: nil, toolUseId: nil, content: nil, isError: nil)
    }

    static func toolResult(id: String, content: String, isError: Bool) -> ClaudeContentBlock {
        ClaudeContentBlock(type: "tool_result", text: nil, source: nil, id: nil, name: nil, input: nil, toolUseId: id, content: content, isError: isError)
    }
}

struct ImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String
    enum CodingKeys: String, CodingKey {
        case type, data
        case mediaType = "media_type"
    }
}

struct ClaudeTool: Encodable {
    let name: String
    let description: String
    let inputSchema: ToolInputSchema

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct ToolInputSchema: Encodable {
    let type: String = "object"
    let properties: [String: ToolProperty]
    let required: [String]
}

struct ToolProperty: Encodable {
    let type: String
    let description: String
}

struct ClaudeResponse: Decodable {
    let id: String?
    let type: String
    let role: String?
    let content: [ClaudeResponseContent]?
    let model: String?
    let stopReason: String?
    let usage: TokenUsage?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model
        case stopReason = "stop_reason"
        case usage
    }
}

struct ClaudeResponseContent: Decodable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: AnyCodable]?
}

struct TokenUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

// MARK: - Streaming event types

enum StreamEvent {
    case messageStart(id: String, model: String)
    case contentBlockStart(index: Int, type: String, id: String?, name: String?)
    case contentBlockDelta(index: Int, delta: ContentDelta)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?, usage: TokenUsage?)
    case messageStop
    case error(String)
    case ping
}

enum ContentDelta {
    case text(String)
    case inputJSON(String)
}

// MARK: - Main client

@MainActor
class ClaudeAPIClient: ObservableObject {
    static let shared = ClaudeAPIClient()

    @Published var isStreaming = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private let maxRetries = 3
    private let retryableStatusCodes: Set<Int> = [429, 503, 529]

    private var apiKey: String? { KeychainManager.shared.anthropicAPIKey }

    // MARK: - Stream API

    func streamMessage(
        messages: [ChatMessage],
        model: ClaudeModel = .haiku,
        systemPrompt: String? = nil,
        tools: [ClaudeTool]? = nil,
        maxTokens: Int = Constants.Agent.maxTokensDefault,
        usePromptCaching: Bool = true,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws {
        guard let key = apiKey, !key.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        let request = try buildRequest(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            tools: tools,
            maxTokens: maxTokens,
            usePromptCaching: usePromptCaching,
            apiKey: key
        )

        isStreaming = true
        defer { isStreaming = false }

        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let (bytes, response) = try await session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ClaudeError.invalidResponse
                }

                if retryableStatusCodes.contains(httpResponse.statusCode) && attempt < maxRetries - 1 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                        .flatMap(Double.init) ?? Double(1 << attempt)
                    NaviLog.warning("API \(httpResponse.statusCode) — retry om \(retryAfter)s (försök \(attempt + 1)/\(maxRetries))")
                    try? await Task.sleep(for: .seconds(retryAfter))
                    continue
                }

                guard httpResponse.statusCode == 200 else {
                    var errorData = Data()
                    for try await byte in bytes { errorData.append(byte) }
                    let msg = String(data: errorData, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                    throw ClaudeError.apiError(httpResponse.statusCode, msg)
                }

                let parser = ClaudeStreamParser()
                for try await line in bytes.lines {
                    if let event = parser.parse(line: line) {
                        onEvent(event)
                    }
                }
                return
            } catch let error as ClaudeError {
                throw error
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = Double(1 << attempt)
                    NaviLog.warning("Nätverksfel — retry om \(delay)s: \(error.localizedDescription)")
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
        throw lastError ?? ClaudeError.invalidResponse
    }

    // MARK: - Non-streaming (for simple queries)

    func sendMessage(
        messages: [ChatMessage],
        model: ClaudeModel = .haiku,
        systemPrompt: String? = nil,
        maxTokens: Int = Constants.Agent.maxTokensDefault
    ) async throws -> (text: String, usage: TokenUsage) {
        guard let key = apiKey, !key.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        var request = try buildRequest(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            tools: nil,
            maxTokens: maxTokens,
            usePromptCaching: true,
            apiKey: key,
            stream: false
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ClaudeError.invalidResponse
                }

                if retryableStatusCodes.contains(httpResponse.statusCode) && attempt < maxRetries - 1 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                        .flatMap(Double.init) ?? Double(1 << attempt)
                    try? await Task.sleep(for: .seconds(retryAfter))
                    continue
                }

                guard httpResponse.statusCode == 200 else {
                    let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw ClaudeError.apiError(httpResponse.statusCode, msg)
                }

                let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
                let text = decoded.content?.first(where: { $0.type == "text" })?.text ?? ""
                let usage = decoded.usage ?? TokenUsage(inputTokens: 0, outputTokens: 0, cacheCreationInputTokens: nil, cacheReadInputTokens: nil)
                return (text, usage)
            } catch let error as ClaudeError {
                throw error
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(for: .seconds(Double(1 << attempt)))
                }
            }
        }
        throw lastError ?? ClaudeError.invalidResponse
    }

    // MARK: - Build URLRequest

    private func buildRequest(
        messages: [ChatMessage],
        model: ClaudeModel,
        systemPrompt: String?,
        tools: [ClaudeTool]?,
        maxTokens: Int,
        usePromptCaching: Bool,
        apiKey: String,
        stream: Bool = true
    ) throws -> URLRequest {
        guard let apiURL = URL(string: Constants.API.anthropicBaseURL) else {
            throw ClaudeError.invalidResponse
        }
        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Constants.API.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if usePromptCaching {
            urlRequest.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        }

        let claudeMessages = messages.compactMap { buildClaudeMessage($0) }

        var systemBlocks: [SystemBlock]? = nil
        if let sp = systemPrompt, !sp.isEmpty {
            systemBlocks = [SystemBlock(
                type: "text",
                text: sp,
                cacheControl: usePromptCaching ? CacheControl() : nil
            )]
        }

        let requestBody = ClaudeRequest(
            model: model.rawValue,
            maxTokens: maxTokens,
            messages: claudeMessages,
            system: systemBlocks,
            stream: stream,
            tools: tools
        )

        urlRequest.httpBody = try JSONEncoder().encode(requestBody)
        return urlRequest
    }

    private func buildClaudeMessage(_ message: ChatMessage) -> ClaudeRequestMessage? {
        var blocks: [ClaudeContentBlock] = []

        for content in message.content {
            switch content {
            case .text(let t):
                blocks.append(.text(t))
            case .image(let data, let mime):
                blocks.append(.image(data: data, mimeType: mime))
            case .toolUse(let id, let name, let input):
                blocks.append(ClaudeContentBlock(type: "tool_use", text: nil, source: nil, id: id, name: name, input: input, toolUseId: nil, content: nil, isError: nil))
            case .toolResult(let id, let content, let isError):
                blocks.append(.toolResult(id: id, content: content, isError: isError))
            }
        }

        guard !blocks.isEmpty else { return nil }
        return ClaudeRequestMessage(role: message.role.rawValue, content: blocks)
    }
}

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(Int, String)
    case streamingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Ingen Anthropic API-nyckel hittad. Gå till Inställningar för att lägga till."
        case .invalidResponse: return "Ogiltigt svar från API"
        case .apiError(let code, let msg): return "API-fel \(code): \(msg)"
        case .streamingFailed(let msg): return "Streaming misslyckades: \(msg)"
        }
    }
}
