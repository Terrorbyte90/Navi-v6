import Foundation

// MARK: - xAI API Client (OpenAI-compatible, with full tool calling support)

@MainActor
final class XAIClient: ObservableObject {
    static let shared = XAIClient()

    private let session = URLSession.shared

    private init() {}

    // MARK: - Auth

    private var apiKey: String? {
        KeychainManager.shared.xaiAPIKey
    }

    private func authHeaders() throws -> [String: String] {
        guard let key = apiKey, !key.isEmpty else {
            throw XAIError.noAPIKey
        }
        return [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json"
        ]
    }

    // MARK: - Build messages (with tool call / tool result support)

    private func buildAPIMessages(
        messages: [ChatMessage],
        systemPrompt: String?
    ) -> [[String: Any]] {
        var apiMessages: [[String: Any]] = []

        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(["role": "system", "content": sys])
        }

        for msg in messages {
            // Handle tool result messages
            let hasToolResults = msg.content.contains { block in
                if case .toolResult = block { return true }
                return false
            }
            if hasToolResults {
                for block in msg.content {
                    if case .toolResult(let id, let content, _) = block {
                        apiMessages.append([
                            "role": "tool",
                            "tool_call_id": id,
                            "content": content
                        ])
                    }
                }
                continue
            }

            // Handle assistant messages with tool_use blocks
            let hasToolUse = msg.content.contains { block in
                if case .toolUse = block { return true }
                return false
            }
            if hasToolUse && msg.role == .assistant {
                var textParts = ""
                var toolCalls: [[String: Any]] = []
                for block in msg.content {
                    switch block {
                    case .text(let t):
                        textParts += t
                    case .toolUse(let id, let name, let input):
                        let jsonData = try? JSONSerialization.data(withJSONObject: input.mapValues { $0.value })
                        let jsonStr = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        toolCalls.append([
                            "id": id,
                            "type": "function",
                            "function": [
                                "name": name,
                                "arguments": jsonStr
                            ] as [String: Any]
                        ])
                    default:
                        break
                    }
                }
                var assistantMsg: [String: Any] = ["role": "assistant"]
                if !textParts.isEmpty {
                    assistantMsg["content"] = textParts
                } else {
                    assistantMsg["content"] = NSNull()
                }
                if !toolCalls.isEmpty {
                    assistantMsg["tool_calls"] = toolCalls
                }
                apiMessages.append(assistantMsg)
                continue
            }

            let role = msg.role == .user ? "user" : "assistant"

            // Check for image content (multimodal)
            let hasImages = msg.content.contains { block in
                if case .image = block { return true }
                return false
            }

            if hasImages && role == "user" {
                var parts: [[String: Any]] = []
                for block in msg.content {
                    switch block {
                    case .text(let t):
                        if !t.isEmpty { parts.append(["type": "text", "text": t]) }
                    case .image(let data, let mimeType):
                        let b64 = data.base64EncodedString()
                        parts.append([
                            "type": "image_url",
                            "image_url": ["url": "data:\(mimeType);base64,\(b64)"]
                        ])
                    default:
                        break
                    }
                }
                if !parts.isEmpty {
                    apiMessages.append(["role": role, "content": parts])
                }
            } else {
                let text = msg.content.compactMap { block -> String? in
                    if case .text(let t) = block { return t }
                    return nil
                }.joined()
                apiMessages.append(["role": role, "content": text])
            }
        }

        return apiMessages
    }

    // MARK: - Chat Completion (streaming, emits StreamEvent for ChatManager compat)

    func streamChatCompletion(
        messages: [ChatMessage],
        model: ClaudeModel,
        systemPrompt: String? = nil,
        maxTokens: Int = Constants.Agent.maxTokensDefault,
        tools: [ClaudeTool]? = nil,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws {
        let headers = try authHeaders()
        let apiMessages = buildAPIMessages(messages: messages, systemPrompt: systemPrompt)

        var body: [String: Any] = [
            "model": model.rawValue,
            "messages": apiMessages,
            "max_tokens": maxTokens,
            "stream": true
        ]

        // Add tools if provided (OpenAI function calling format)
        if let tools, !tools.isEmpty {
            body["tools"] = OpenRouterClient.openAITools(from: tools)
        }

        var request = URLRequest(url: URL(string: Constants.API.xaiChatEndpoint)!)
        request.httpMethod = "POST"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let toolCount = tools?.count ?? 0
        NaviLog.info("xAI stream → \(model.rawValue) (tools: \(toolCount))")

        onEvent(.messageStart(id: UUID().uuidString, model: model.rawValue))

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw XAIError.invalidResponse
        }
        guard httpResp.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            throw XAIError.apiError(httpResp.statusCode, errorBody)
        }

        var inputTokens = 0
        var outputTokens = 0

        // Track tool calls from streaming deltas
        var pendingToolCalls: [Int: (id: String, name: String, arguments: String)] = [:]
        var hasToolCalls = false
        var stopReason = "end_turn"

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            if jsonStr == "[DONE]" {
                let usage = TokenUsage(
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheCreationInputTokens: nil,
                    cacheReadInputTokens: nil
                )
                // Emit contentBlockStop for each pending tool call
                for (idx, _) in pendingToolCalls {
                    onEvent(.contentBlockStop(index: idx + 1))
                }
                onEvent(.messageDelta(stopReason: stopReason, usage: usage))
                onEvent(.messageStop)
                break
            }

            guard let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            // Extract usage if present
            if let usage = obj["usage"] as? [String: Any] {
                inputTokens = usage["prompt_tokens"] as? Int ?? inputTokens
                outputTokens = usage["completion_tokens"] as? Int ?? outputTokens
            }

            // Extract choices
            if let choices = obj["choices"] as? [[String: Any]],
               let first = choices.first {

                if let delta = first["delta"] as? [String: Any] {
                    // Handle text content
                    if let content = delta["content"] as? String {
                        onEvent(.contentBlockDelta(index: 0, delta: .text(content)))
                    }

                    // Handle streaming tool calls (OpenAI format)
                    if let toolCallDeltas = delta["tool_calls"] as? [[String: Any]] {
                        for tc in toolCallDeltas {
                            let idx = tc["index"] as? Int ?? 0

                            // New tool call start
                            if let id = tc["id"] as? String {
                                let funcInfo = tc["function"] as? [String: Any]
                                let name = funcInfo?["name"] as? String ?? ""
                                let args = funcInfo?["arguments"] as? String ?? ""
                                pendingToolCalls[idx] = (id: id, name: name, arguments: args)
                                hasToolCalls = true

                                onEvent(.contentBlockStart(index: idx + 1, type: "tool_use", id: id, name: name))
                            }

                            // Append to existing tool call arguments
                            if let funcInfo = tc["function"] as? [String: Any],
                               let argChunk = funcInfo["arguments"] as? String,
                               var existing = pendingToolCalls[idx] {
                                if tc["id"] == nil {
                                    existing.arguments += argChunk
                                    pendingToolCalls[idx] = existing
                                }
                                if let name = funcInfo["name"] as? String, !name.isEmpty {
                                    existing.name = name
                                    pendingToolCalls[idx] = existing
                                }
                                onEvent(.contentBlockDelta(index: idx + 1, delta: .inputJSON(argChunk)))
                            }
                        }
                    }
                }

                // Handle finish_reason
                if let finish = first["finish_reason"] as? String {
                    if finish == "tool_calls" {
                        stopReason = "tool_use"
                    } else if finish == "stop" {
                        stopReason = "end_turn"
                    }
                }
            }
        }
    }

    // MARK: - Chat Completion (non-streaming)

    func chatCompletion(
        messages: [ChatMessage],
        model: ClaudeModel,
        systemPrompt: String? = nil,
        maxTokens: Int = Constants.Agent.maxTokensDefault
    ) async throws -> (String, TokenUsage) {
        let headers = try authHeaders()

        var apiMessages: [[String: Any]] = []
        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(["role": "system", "content": sys])
        }
        for msg in messages {
            let role = msg.role == .user ? "user" : "assistant"
            let text = msg.content.compactMap { block -> String? in
                if case .text(let t) = block { return t }
                return nil
            }.joined()
            apiMessages.append(["role": role, "content": text])
        }

        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": apiMessages,
            "max_tokens": maxTokens
        ]

        var request = URLRequest(url: URL(string: Constants.API.xaiChatEndpoint)!)
        request.httpMethod = "POST"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw XAIError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0, body)
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw XAIError.invalidResponse
        }

        let usage: TokenUsage
        if let u = obj["usage"] as? [String: Any] {
            usage = TokenUsage(
                inputTokens: u["prompt_tokens"] as? Int ?? 0,
                outputTokens: u["completion_tokens"] as? Int ?? 0,
                cacheCreationInputTokens: nil,
                cacheReadInputTokens: nil
            )
        } else {
            usage = TokenUsage(inputTokens: 0, outputTokens: 0, cacheCreationInputTokens: nil, cacheReadInputTokens: nil)
        }

        return (content, usage)
    }

    // MARK: - Image Generation (grok-2-aurora)

    func generateImage(
        prompt: String,
        model: String = "grok-2-aurora",
        size: String = "1024x1024",   // kept for API compat but not sent to xAI
        n: Int = 1
    ) async throws -> [XAIImageResult] {
        let headers = try authHeaders()

        // xAI Aurora image API
        // Note: response_format "b64_json" is preferred to avoid CDN download issues
        // If the model doesn't support b64_json, we fall back to URL-based downloads
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": n,
            "response_format": "b64_json"
        ]

        var request = URLRequest(url: URL(string: Constants.API.xaiImageEndpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw XAIError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0, errBody)
        }

        // Log raw response so mismatches are visible
        let rawBody = String(data: data, encoding: .utf8) ?? "(non-utf8)"
        NaviLog.info("XAI bildgenerering svar: \(rawBody.prefix(800))")

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NaviLog.error("XAI bildgenerering: ej JSON-svar")
            throw XAIError.invalidResponse
        }

        // Some APIs embed errors inside a 200 response body
        if let errObj = obj["error"] as? [String: Any] {
            let msg = (errObj["message"] as? String) ?? (errObj["code"] as? String) ?? rawBody
            throw XAIError.apiError(200, msg)
        }
        if let errStr = obj["error"] as? String {
            throw XAIError.apiError(200, errStr)
        }

        // Support both standard "data" key and possible "images" key
        let items: [[String: Any]]
        if let d = obj["data"] as? [[String: Any]] {
            items = d
        } else if let d = obj["images"] as? [[String: Any]] {
            items = d
        } else {
            NaviLog.error("XAI bildgenerering: hittar ej data[]/images[] i svar. Nycklar: \(Array(obj.keys))")
            throw XAIError.invalidResponse
        }

        let results = items.compactMap { item -> XAIImageResult? in
            // Prefer b64_json over URL — CDN URLs from imgen.x.ai fail on iOS
            if let b64 = item["b64_json"] as? String {
                return XAIImageResult(b64: b64, revisedPrompt: item["revised_prompt"] as? String)
            }
            if let url = item["url"] as? String {
                return XAIImageResult(url: url, revisedPrompt: item["revised_prompt"] as? String)
            }
            return nil
        }
        guard !results.isEmpty else {
            NaviLog.error("XAI bildgenerering: data-array har inga url/b64_json-objekt: \(items)")
            throw XAIError.invalidResponse
        }
        return results
    }

    // MARK: - Video Generation (grok-imagine-video)

    /// Submit a video generation task and poll until complete. Returns the finished video Data.
    /// Docs: POST https://api.x.ai/v1/videos/generations  → { "request_id": "..." }
    ///       GET  https://api.x.ai/v1/videos/{request_id} → { "status": "done", "video": { "url": "..." } }
    func generateVideo(
        prompt: String,
        imageData: Data? = nil,
        duration: Int = 5,
        aspectRatio: String = "9:16"
    ) async throws -> Data {
        let headers = try authHeaders()

        var body: [String: Any] = [
            "model": "grok-imagine-video",
            "prompt": prompt,
            "duration": duration,
            "aspect_ratio": aspectRatio
        ]

        // Image-to-video: pass as data URI (xAI accepts base64 data URIs for image_url)
        if let img = imageData {
            let base64 = img.base64EncodedString()
            body["image_url"] = "data:image/jpeg;base64,\(base64)"
        }

        var request = URLRequest(url: URL(string: Constants.API.xaiVideoEndpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw XAIError.invalidResponse
        }
        guard httpResp.statusCode == 200 || httpResp.statusCode == 202 else {
            let errBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            NaviLog.error("XAI videogenerering HTTP \(httpResp.statusCode): \(errBody.prefix(300))")
            throw XAIError.apiError(httpResp.statusCode, errBody)
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NaviLog.error("XAI videogenerering: ej JSON-svar")
            throw XAIError.invalidResponse
        }

        NaviLog.info("XAI videogenerering svar: \(String(data: data, encoding: .utf8)?.prefix(400) ?? "")")

        // Rare: synchronous response already includes video.url
        if let video = obj["video"] as? [String: Any],
           let videoURL = video["url"] as? String {
            NaviLog.info("XAI video: synkront svar, laddar ner direkt")
            return try await downloadData(from: videoURL)
        }

        // Normal: async task, poll using request_id
        guard let requestId = obj["request_id"] as? String else {
            NaviLog.error("XAI videogenerering: saknar request_id. Nycklar: \(Array(obj.keys))")
            throw XAIError.invalidResponse
        }

        NaviLog.info("XAI videogenerering startat, request_id=\(requestId)")
        return try await pollVideoTask(requestId: requestId, headers: headers)
    }

    /// Polls GET https://api.x.ai/v1/videos/{request_id} every 5s until status == "done".
    private func pollVideoTask(requestId: String, headers: [String: String]) async throws -> Data {
        // Poll URL: /v1/videos/{request_id}  — different from /v1/videos/generations/{id}
        let statusURL = URL(string: "\(Constants.API.xaiVideoPollBase)/\(requestId)")!
        let maxAttempts = 72 // 72 × 5s = 6 min max

        for attempt in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5s

            var req = URLRequest(url: statusURL)
            req.httpMethod = "GET"
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

            let (data, response) = try await session.data(for: req)

            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                NaviLog.error("XAI videostatus HTTP \(code) vid försök \(attempt)")
                throw XAIError.invalidResponse
            }

            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw XAIError.invalidResponse
            }

            let status = obj["status"] as? String ?? "pending"
            NaviLog.info("XAI videostatus [\(attempt)]: \(status)")

            switch status {
            case "done":
                // { "status": "done", "video": { "url": "...", "duration": N }, "model": "grok-imagine-video" }
                if let video = obj["video"] as? [String: Any],
                   let videoURL = video["url"] as? String {
                    NaviLog.info("XAI video klar, laddar ner")
                    return try await downloadData(from: videoURL)
                }
                NaviLog.error("XAI video done men saknar video.url. Nycklar: \(Array(obj.keys))")
                throw XAIError.invalidResponse

            case "failed", "cancelled", "expired":
                let reason = (obj["error"] as? String)
                    ?? (obj["message"] as? String)
                    ?? "Videogenerering misslyckades (status: \(status))"
                throw XAIError.apiError(0, reason)

            default:
                // "pending" → continue polling
                break
            }
        }

        throw XAIError.apiError(0, "Videogenerering tog för lång tid (timeout efter \(maxAttempts * 5)s).")
    }

    // MARK: - Download data from URL

    func downloadImageData(from urlString: String) async throws -> Data {
        try await downloadData(from: urlString)
    }

    func downloadData(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw XAIError.invalidResponse
        }
        let (data, _) = try await session.data(from: url)
        return data
    }

    // MARK: - Balance

    func fetchBalance() async throws -> XAIBalance {
        let headers = try authHeaders()

        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/api-key")!)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await session.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            // Balance API might not be available — return unknown
            return XAIBalance(remainingCredits: nil, totalCredits: nil)
        }

        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let remaining = obj["remaining_balance"] as? Double
                ?? obj["api_limit_remaining"] as? Double
            let total = obj["total_balance"] as? Double
                ?? obj["api_limit_monthly"] as? Double
            return XAIBalance(remainingCredits: remaining, totalCredits: total)
        }

        return XAIBalance(remainingCredits: nil, totalCredits: nil)
    }
}

// MARK: - Types

struct XAIImageResult {
    let url: String?       // HTTP URL to download (nil if b64)
    let b64: String?       // Base64 PNG data (nil if url)
    let revisedPrompt: String?

    init(url: String, revisedPrompt: String? = nil) {
        self.url = url; self.b64 = nil; self.revisedPrompt = revisedPrompt
    }
    init(b64: String, revisedPrompt: String? = nil) {
        self.url = nil; self.b64 = b64; self.revisedPrompt = revisedPrompt
    }
}

struct XAIBalance {
    let remainingCredits: Double?
    let totalCredits: Double?

    var formattedRemaining: String {
        guard let r = remainingCredits else { return "Okänt" }
        return String(format: "$%.2f", r)
    }

    @MainActor
    var formattedRemainingInSEK: String {
        guard let r = remainingCredits else { return "—" }
        let sek = r * ExchangeRateService.shared.usdToSEK
        return String(format: "%.0f kr", sek)
    }
}

enum XAIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Ingen xAI API-nyckel konfigurerad. Lägg till en i Inställningar."
        case .invalidResponse: return "Ogiltigt svar från xAI API."
        case .apiError(let code, let body): return "xAI API-fel (\(code)): \(body.prefix(200))"
        }
    }
}
