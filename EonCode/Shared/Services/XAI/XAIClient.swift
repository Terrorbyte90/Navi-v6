import Foundation

// MARK: - xAI API Client (OpenAI-compatible)

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

    // MARK: - Chat Completion (streaming, emits StreamEvent for ChatManager compat)

    func streamChatCompletion(
        messages: [ChatMessage],
        model: ClaudeModel,
        systemPrompt: String? = nil,
        maxTokens: Int = Constants.Agent.maxTokensDefault,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws {
        let headers = try authHeaders()

        // Build OpenAI-compatible messages
        var apiMessages: [[String: Any]] = []
        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(["role": "system", "content": sys])
        }
        for msg in messages {
            let role = msg.role == .user ? "user" : "assistant"
            // Extract text from content blocks
            let text = msg.content.compactMap { block -> String? in
                if case .text(let t) = block { return t }
                return nil
            }.joined()
            apiMessages.append(["role": role, "content": text])
        }

        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": apiMessages,
            "max_tokens": maxTokens,
            "stream": true
        ]

        var request = URLRequest(url: URL(string: Constants.API.xaiChatEndpoint)!)
        request.httpMethod = "POST"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            if jsonStr == "[DONE]" {
                onEvent(.messageDelta(
                    stopReason: "end_turn",
                    usage: TokenUsage(
                        inputTokens: inputTokens,
                        outputTokens: outputTokens,
                        cacheCreationInputTokens: nil,
                        cacheReadInputTokens: nil
                    )
                ))
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

            // Extract delta text
            if let choices = obj["choices"] as? [[String: Any]],
               let first = choices.first,
               let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                onEvent(.contentBlockDelta(index: 0, delta: .text(content)))
            }

            // Check for finish_reason
            if let choices = obj["choices"] as? [[String: Any]],
               let first = choices.first,
               let finish = first["finish_reason"] as? String, finish == "stop" {
                // Will be handled by [DONE]
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

    // MARK: - Image Generation (Aurora)

    func generateImage(
        prompt: String,
        model: String = "grok-imagine-image",
        size: String = "1024x1024",
        n: Int = 1
    ) async throws -> [XAIImageResult] {
        let headers = try authHeaders()

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": n,
            "size": size,
            "response_format": "url"
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

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = obj["data"] as? [[String: Any]] else {
            throw XAIError.invalidResponse
        }

        return dataArr.compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            return XAIImageResult(url: url, revisedPrompt: item["revised_prompt"] as? String)
        }
    }

    // MARK: - Download image data from URL

    func downloadImageData(from urlString: String) async throws -> Data {
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
    let url: String
    let revisedPrompt: String?
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
