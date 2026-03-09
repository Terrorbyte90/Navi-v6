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
        model: String = "grok-2-image",
        size: String = "1024x1024",   // kept for API compat but not sent to xAI
        n: Int = 1
    ) async throws -> [XAIImageResult] {
        let headers = try authHeaders()

        // xAI Aurora image API — only accepts model, prompt, n
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": n
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
            if let url = item["url"] as? String {
                return XAIImageResult(url: url, revisedPrompt: item["revised_prompt"] as? String)
            }
            if let b64 = item["b64_json"] as? String {
                return XAIImageResult(b64: b64, revisedPrompt: item["revised_prompt"] as? String)
            }
            return nil
        }
        guard !results.isEmpty else {
            NaviLog.error("XAI bildgenerering: data-array har inga url/b64_json-objekt: \(items)")
            throw XAIError.invalidResponse
        }
        return results
    }

    // MARK: - Video Generation (Aurora)

    /// Submit a video generation task and poll until complete. Returns the finished video Data.
    func generateVideo(
        prompt: String,
        imageData: Data? = nil,
        duration: Int = 5,
        aspectRatio: String = "9:16"
    ) async throws -> Data {
        let headers = try authHeaders()

        var body: [String: Any] = [
            "model": "aurora",
            "prompt": prompt,
            "duration": duration,
            "aspect_ratio": aspectRatio
        ]

        if let img = imageData {
            let base64 = img.base64EncodedString()
            body["input_image"] = "data:image/jpeg;base64,\(base64)"
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
            throw XAIError.apiError(httpResp.statusCode, errBody)
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw XAIError.invalidResponse
        }

        // Synchronous response: data[0].url present immediately
        if let dataArr = obj["data"] as? [[String: Any]],
           let first = dataArr.first,
           let videoURL = first["url"] as? String {
            return try await downloadData(from: videoURL)
        }

        // Async/task-based response: poll using task id
        guard let taskId = obj["id"] as? String else {
            throw XAIError.invalidResponse
        }

        return try await pollVideoTask(taskId: taskId, headers: headers)
    }

    private func pollVideoTask(taskId: String, headers: [String: String]) async throws -> Data {
        let statusURL = URL(string: "\(Constants.API.xaiVideoEndpoint)/\(taskId)")!
        let maxAttempts = 60

        for _ in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5s

            var req = URLRequest(url: statusURL)
            req.httpMethod = "GET"
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

            let (data, response) = try await session.data(for: req)

            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                throw XAIError.invalidResponse
            }

            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw XAIError.invalidResponse
            }

            let status = obj["status"] as? String ?? ""

            if status == "succeeded" || status == "completed" {
                if let dataArr = obj["data"] as? [[String: Any]],
                   let first = dataArr.first,
                   let videoURL = first["url"] as? String {
                    return try await downloadData(from: videoURL)
                }
                if let videoURL = obj["output_url"] as? String {
                    return try await downloadData(from: videoURL)
                }
                throw XAIError.invalidResponse
            }

            if status == "failed" || status == "cancelled" {
                let reason = obj["error"] as? String ?? "Okänt fel"
                throw XAIError.apiError(0, reason)
            }
        }

        throw XAIError.apiError(0, "Videogenerering tog för lång tid (timeout).")
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
