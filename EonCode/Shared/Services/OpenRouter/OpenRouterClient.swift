import Foundation

// MARK: - OpenRouter API Client (OpenAI-compatible)
// Completely reworked for reliability with all OpenRouter models.

@MainActor
final class OpenRouterClient: ObservableObject {
    static let shared = OpenRouterClient()

    private let session = URLSession.shared

    private init() {}

    // MARK: - Auth

    private var apiKey: String? {
        KeychainManager.shared.openRouterAPIKey
    }

    private func authHeaders() throws -> [String: String] {
        guard let key = apiKey, !key.isEmpty else {
            throw OpenRouterError.noAPIKey
        }
        return [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://navi.app",
            "X-Title": "Navi"
        ]
    }

    // MARK: - Build messages array

    private func buildAPIMessages(
        messages: [ChatMessage],
        systemPrompt: String?
    ) -> [[String: Any]] {
        var apiMessages: [[String: Any]] = []

        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(["role": "system", "content": sys])
        }

        for msg in messages {
            let role = msg.role == .user ? "user" : "assistant"

            // Check if message has image content (multimodal)
            let hasImages = msg.content.contains { block in
                if case .image = block { return true }
                return false
            }

            if hasImages && role == "user" {
                // Build OpenAI-compatible multimodal content array
                var parts: [[String: Any]] = []
                for block in msg.content {
                    switch block {
                    case .text(let t):
                        if !t.isEmpty {
                            parts.append(["type": "text", "text": t])
                        }
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
                guard !parts.isEmpty else { continue }
                apiMessages.append(["role": role, "content": parts])
            } else {
                let text = msg.content.compactMap { block -> String? in
                    if case .text(let t) = block { return t }
                    return nil
                }.joined()
                guard !text.isEmpty else { continue }
                apiMessages.append(["role": role, "content": text])
            }
        }

        return apiMessages
    }

    // MARK: - Chat Completion (streaming)

    func streamChatCompletion(
        messages: [ChatMessage],
        model: ClaudeModel,
        systemPrompt: String? = nil,
        maxTokens: Int = Constants.Agent.maxTokensDefault,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws {
        let headers = try authHeaders()
        let apiMessages = buildAPIMessages(messages: messages, systemPrompt: systemPrompt)

        guard apiMessages.contains(where: { ($0["role"] as? String) == "user" }) else {
            throw OpenRouterError.emptyRequest
        }

        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": apiMessages,
            "max_tokens": maxTokens,
            "stream": true
        ]

        guard let url = URL(string: Constants.API.openRouterBaseURL) else {
            throw OpenRouterError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        NaviLog.info("OpenRouter stream → \(model.rawValue)")

        onEvent(.messageStart(id: UUID().uuidString, model: model.rawValue))

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard httpResp.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            NaviLog.error("OpenRouter HTTP \(httpResp.statusCode): \(errorBody.prefix(500))")
            let message = Self.parseErrorMessage(from: errorBody) ?? "HTTP \(httpResp.statusCode)"
            throw OpenRouterError.apiError(httpResp.statusCode, message)
        }

        var inputTokens = 0
        var outputTokens = 0
        var hasEmittedContent = false

        for try await line in bytes.lines {
            // Skip empty lines
            guard !line.isEmpty else { continue }
            
            // Skip SSE comments (lines starting with ":")
            if line.hasPrefix(":") { continue }

            // Must be a data line - handle both "data:" and "data: " formats
            guard line.hasPrefix("data:") else { continue }

            // Extract payload
            let payload: String
            if line.hasPrefix("data: ") {
                payload = String(line.dropFirst(6))
            } else if line.hasPrefix("data:") {
                payload = String(line.dropFirst(5))
            } else {
                continue
            }

            // Stream termination
            if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                NaviLog.info("OpenRouter stream [DONE]")
                break
            }

            guard !payload.isEmpty else { continue }

            // Parse JSON chunk
            guard let jsonData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else {
                NaviLog.info("OpenRouter skippar icke-JSON: \(payload.prefix(100))")
                continue
            }

            // Check for top-level error (mid-stream error)
            if let error = json["error"] as? [String: Any] {
                let errorMsg = error["message"] as? String ?? "Okänt OpenRouter-fel"
                let errorCode = error["code"] as? Int ?? 500
                NaviLog.error("OpenRouter mitt-i-strömmen fel: \(errorMsg)")
                throw OpenRouterError.apiError(errorCode, errorMsg)
            }

            // Extract usage
            if let usage = json["usage"] as? [String: Any] {
                inputTokens = usage["prompt_tokens"] as? Int ?? inputTokens
                outputTokens = usage["completion_tokens"] as? Int ?? outputTokens
            }

            // Extract choices
            guard let choices = json["choices"] as? [[String: Any]],
                  let choice = choices.first else { continue }

            // Check for finish_reason = "error" (mid-stream error format)
            if let finishReason = choice["finish_reason"] as? String,
               finishReason == "error" {
                let errorMsg = (json["error"] as? [String: Any])?["message"] as? String
                    ?? "Modellen returnerade ett fel"
                NaviLog.error("OpenRouter finish_reason=error: \(errorMsg)")
                throw OpenRouterError.apiError(500, errorMsg)
            }

            // Extract delta content - handle optional content field
            if let delta = choice["delta"] as? [String: Any] {
                // Handle reasoning_content (chain-of-thought) - skip it
                // Only emit actual content
                if let content = delta["content"] as? String, !content.isEmpty {
                    hasEmittedContent = true
                    onEvent(.contentBlockDelta(index: 0, delta: .text(content)))
                }
            }

            // Handle normal finish
            if let finishReason = choice["finish_reason"] as? String,
               finishReason == "stop" || finishReason == "length" {
                break
            }
        }

        // Fallback if no content was emitted
        if !hasEmittedContent {
            NaviLog.error("OpenRouter stream tom – ingen content för \(model.displayName)")
            onEvent(.contentBlockDelta(
                index: 0,
                delta: .text("(Inget svar från \(model.displayName). Försök igen eller välj en annan modell.)")
            ))
        }

        let usage = TokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationInputTokens: nil,
            cacheReadInputTokens: nil
        )
        onEvent(.messageDelta(stopReason: "end_turn", usage: usage))
        onEvent(.messageStop)
        
        NaviLog.info("OpenRouter stream klar – \(outputTokens) output tokens")
    }

    // MARK: - Chat Completion (non-streaming)

    func chatCompletion(
        messages: [ChatMessage],
        model: ClaudeModel,
        systemPrompt: String? = nil,
        maxTokens: Int = Constants.Agent.maxTokensDefault
    ) async throws -> (String, TokenUsage) {
        let headers = try authHeaders()
        let apiMessages = buildAPIMessages(messages: messages, systemPrompt: systemPrompt)

        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": apiMessages,
            "max_tokens": maxTokens
        ]

        guard let url = URL(string: Constants.API.openRouterBaseURL) else {
            throw OpenRouterError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        NaviLog.info("OpenRouter non-stream → \(model.rawValue)")

        let (data, response) = try await session.data(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard httpResp.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? "Okänt fel"
            NaviLog.error("OpenRouter HTTP \(httpResp.statusCode): \(errBody.prefix(500))")
            let message = Self.parseErrorMessage(from: errBody) ?? errBody
            throw OpenRouterError.apiError(httpResp.statusCode, message)
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenRouterError.invalidResponse
        }

        if let error = obj["error"] as? [String: Any],
           let errorMsg = error["message"] as? String {
            throw OpenRouterError.apiError(0, errorMsg)
        }

        guard let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenRouterError.invalidResponse
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

    // MARK: - Test Connection

    /// Quick test to verify API key works
    func testConnection() async throws -> Bool {
        let headers = try authHeaders()

        let body: [String: Any] = [
            "model": Constants.Models.minimaxM25,
            "messages": [["role": "user", "content": "Hi"]],
            "max_tokens": 10
        ]

        guard let url = URL(string: Constants.API.openRouterBaseURL) else {
            throw OpenRouterError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        if httpResp.statusCode == 401 {
            throw OpenRouterError.apiError(401, "Ogiltig API-nyckel")
        }

        return httpResp.statusCode == 200
    }

    // MARK: - Error parsing

    private static func parseErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let message = json["message"] as? String {
            return message
        }
        return nil
    }
}

// MARK: - Errors

enum OpenRouterError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case emptyRequest
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Ingen OpenRouter API-nyckel hittad. Gå till Inställningar."
        case .invalidResponse:
            return "Ogiltigt svar från OpenRouter."
        case .emptyRequest:
            return "Inga meddelanden att skicka till OpenRouter."
        case .apiError(let code, let msg):
            return "OpenRouter (\(code)): \(msg)"
        }
    }
}
